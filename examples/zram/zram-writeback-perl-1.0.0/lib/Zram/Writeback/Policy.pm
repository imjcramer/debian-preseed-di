package Zram::Writeback::Policy;

use strict;
use warnings;
use Zram::Writeback::Budget;
use Zram::Writeback::BlockState;
use Zram::Writeback::Lock;
use Zram::Writeback::Pressure;
use Zram::Writeback::Util qw(log_msg parse_list);

sub new {
    my ($class, %arg) = @_;
    my $cfg = $arg{cfg} or die q{cfg is required};
    my $device = $arg{device} or die q{device is required};
    return bless { cfg => $cfg, device => $device }, $class;
}

sub run_once {
    my ($self, %opt) = @_;
    my $cfg = $self->{cfg};
    my $lock_path = $cfg->get('lock', 'lock_file', '/run/lock/zram-writeback.lock');
    my $lock = Zram::Writeback::Lock->new(path => $lock_path)->acquire;

    my ($state, $reasons, $sample);
    if ($opt{state_override}) {
        $state = lc $opt{state_override};
        die "invalid state override: $state" unless $state =~ /\A(?:normal|pressure|emergency)\z/;
        $reasons = ['operator override'];
        $sample = {};
    } else {
        my $pressure = Zram::Writeback::Pressure->new(cfg => $cfg);
        ($state, $reasons, $sample) = $pressure->determine_state;
    }

    log_msg('INFO', 'policy state=' . $state . ' reason=' . join('; ', @$reasons));

    my %result = (
        state => $state,
        reasons => $reasons,
        recompress_passes => 0,
        writeback_passes => 0,
        compact_runs => 0,
    );

    $self->_mark_idle_for_state($state);

    my @passes = $self->_ordered_passes;
    for my $p (grep { $_->{operation} eq 'recompress' } @passes) {
        next unless $self->_pass_should_run($p, $state);
        my $max_pages = $self->_max_pages_for_state($p, $state);
        next if defined($max_pages) && $max_pages <= 0;
        $self->{device}->recompress(
            type      => $p->{type},
            priority  => $p->{priority},
            threshold => $p->{threshold_bytes},
            max_pages => $max_pages,
        );
        ++$result{recompress_passes};
        log_msg('INFO', "recompress pass=$p->{section} type=$p->{type} priority=$p->{priority} max_pages=" . (defined($max_pages) ? $max_pages : 'unlimited'));
    }

    if ($result{recompress_passes} && $cfg->get_bool('compact', 'after_recompress', 1)) {
        $self->{device}->compact;
        ++$result{compact_runs};
    }

    my $budget = Zram::Writeback::Budget->new(cfg => $cfg, device => $self->{device});
    $budget->maybe_emergency_topup if $state eq 'emergency';

    my $targeted_writeback = $self->_maybe_page_index_writeback($state, $budget);
    if ($targeted_writeback) {
        ++$result{writeback_passes};
    }

    my $replace_generic = $cfg->get_bool('page_index_targeting', 'replace_generic_writeback', 0);
    for my $p (grep { $_->{operation} eq 'writeback' } @passes) {
        next if $replace_generic && $targeted_writeback;
        next unless $self->_pass_should_run($p, $state);
        if ($p->{requires_budget} && !$budget->has_budget_for_required_pass) {
            log_msg('WARN', "writeback skipped for $p->{section}: budget floor reached or unavailable");
            next;
        }
        $self->{device}->writeback_type($p->{type});
        ++$result{writeback_passes};
        log_msg('INFO', "writeback pass=$p->{section} type=$p->{type}");
    }

    if ($result{writeback_passes} && $cfg->get_bool('compact', 'after_writeback', 1)) {
        $self->{device}->compact;
        ++$result{compact_runs};
    }

    $lock->release;
    return \%result;
}


sub _maybe_page_index_writeback {
    my ($self, $state, $budget) = @_;
    my $cfg = $self->{cfg};
    return 0 unless $cfg->get_bool('page_index_targeting', 'enabled', 0);
    return 0 if $state eq 'normal';
    return 0 unless $budget->has_budget_for_required_pass;

    my $path = $cfg->get('page_index_targeting', 'block_state', '');
    return 0 unless $path ne '' && -r $path;

    my $max_indexes = $cfg->get_int('page_index_targeting', 'max_indexes_per_pass', 8192);
    my $max_ranges = $cfg->get_int('page_index_targeting', 'max_ranges_per_write', 128);
    my @prefer = parse_list($cfg->get('page_index_targeting', 'prefer_states', 'n,hi'));
    my @avoid = parse_list($cfg->get('page_index_targeting', 'avoid_states', 's,w'));

    my $records = Zram::Writeback::BlockState::read_file($path);
    my $indexes = Zram::Writeback::BlockState::select_indexes(
        $records,
        prefer => \@prefer,
        avoid  => \@avoid,
        max    => $max_indexes,
    );
    return 0 unless @$indexes;
    my $ranges = Zram::Writeback::BlockState::indexes_to_ranges($indexes, $max_ranges);
    my $arg = Zram::Writeback::BlockState::ranges_to_writeback_arg($ranges);
    return 0 if $arg eq '';
    $self->{device}->writeback_page_arg($arg);
    log_msg('INFO', 'page-index writeback ranges=' . scalar(@$ranges) . ' indexes=' . scalar(@$indexes));
    return 1;
}

sub _mark_idle_for_state {
    my ($self, $state) = @_;
    my $cfg = $self->{cfg};
    return unless $cfg->get_bool('idle_mark', 'enabled', 1);
    my $key = $state . '_idle_age_sec';
    my $age = $cfg->get_int('idle_mark', $key, 0);
    if ($age > 0) {
        my $ok = eval { $self->{device}->mark_idle($age); 1 };
        if (!$ok) {
            my $err = $@ || 'unknown error';
            if ($cfg->get_bool('idle_mark', 'fallback_mark_all', 0)) {
                log_msg('WARN', "age idle mark failed, falling back to all: $err");
                $self->{device}->mark_idle('all');
            } else {
                die $err;
            }
        }
    }
}

sub _ordered_passes {
    my ($self) = @_;
    my @passes;
    for my $section ($self->{cfg}->sections('pass')) {
        next if $section eq 'pass';
        next unless $self->{cfg}->get_bool($section, 'enabled', 0);
        my %p = %{ $self->{cfg}->section_hash($section) };
        $p{section} = $section;
        $p{priority} = $self->{cfg}->get_int($section, 'priority', 0) if exists $p{priority};
        $p{requires_budget} = $self->{cfg}->get_bool($section, 'requires_budget', 0);
        push @passes, \%p;
    }
    return sort { _pass_sort_key($a) cmp _pass_sort_key($b) } @passes;
}

sub _pass_sort_key {
    my ($p) = @_;
    my $op_order = $p->{operation} eq 'recompress' ? 0 : 1;
    my $type_order = 50;
    if ($p->{operation} eq 'recompress') {
        $type_order = $p->{priority} || 50;
    } elsif ($p->{type} eq 'incompressible') {
        $type_order = 10;
    } elsif ($p->{type} eq 'huge_idle') {
        $type_order = 20;
    } elsif ($p->{type} eq 'huge') {
        $type_order = 25;
    } elsif ($p->{type} eq 'idle') {
        $type_order = 30;
    }
    return sprintf('%02d:%03d:%s', $op_order, $type_order, $p->{section});
}

sub _pass_should_run {
    my ($self, $p, $state) = @_;
    my %run = map { $_ => 1 } parse_list($p->{run_when} || '');
    return $run{$state} ? 1 : 0;
}

sub _max_pages_for_state {
    my ($self, $p, $state) = @_;
    my $key = 'max_pages_' . $state;
    return int($p->{$key}) if exists($p->{$key}) && defined($p->{$key}) && $p->{$key} ne '';
    return int($p->{max_pages}) if exists($p->{max_pages}) && defined($p->{max_pages}) && $p->{max_pages} ne '';
    return undef;
}

1;
