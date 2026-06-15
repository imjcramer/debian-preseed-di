package Zram::Writeback::Budget;

use strict;
use warnings;
use Zram::Writeback::Util qw(ensure_dir now_date log_msg);

sub new {
    my ($class, %arg) = @_;
    return bless { cfg => $arg{cfg}, device => $arg{device} }, $class;
}

sub mib_to_units {
    my ($mib) = @_;
    return int(($mib + 0) * 1024 * 1024 / 4096);
}

sub daily_units {
    my ($self) = @_;
    my $mib = $self->{cfg}->get_int('writeback_budget', 'daily_budget_mib', 0);
    return mib_to_units($mib);
}

sub emergency_units {
    my ($self) = @_;
    my $mib = $self->{cfg}->get_int('writeback_budget', 'emergency_extra_budget_mib', 0);
    return mib_to_units($mib);
}

sub enabled {
    my ($self) = @_;
    return $self->{cfg}->get_bool('writeback_budget', 'enabled', 1);
}

sub reset_daily {
    my ($self) = @_;
    return 1 unless $self->enabled;
    my $units = $self->daily_units;
    $self->{device}->set_writeback_budget($units, 1);
    $self->_write_state({ date => now_date(), emergency_topup_date => '' });
    log_msg('INFO', "writeback daily budget reset to $units units of 4 KiB");
    return 1;
}

sub remaining_units {
    my ($self) = @_;
    return undef unless $self->enabled;
    return $self->{device}->read_writeback_budget;
}

sub has_budget_for_required_pass {
    my ($self) = @_;
    return 1 unless $self->enabled;
    my $remaining = $self->remaining_units;
    return 0 unless defined $remaining;
    my $daily = $self->daily_units;
    my $min_pct = $self->{cfg}->get('writeback_budget', 'min_remaining_budget_pct', 10) + 0;
    my $floor = int($daily * $min_pct / 100.0);
    return $remaining > $floor ? 1 : 0;
}

sub maybe_emergency_topup {
    my ($self) = @_;
    return 0 unless $self->enabled;
    return 0 unless $self->{cfg}->get_bool('writeback_budget', 'emergency_topup_once_daily', 1);
    my $extra = $self->emergency_units;
    return 0 if $extra <= 0;

    my $state = $self->_read_state;
    my $today = now_date();
    return 0 if ($state->{emergency_topup_date} || '') eq $today;

    my $remaining = $self->remaining_units;
    $remaining = 0 unless defined $remaining;
    $self->{device}->set_writeback_budget($remaining + $extra, 1);
    $state->{emergency_topup_date} = $today;
    $self->_write_state($state);
    log_msg('WARN', "emergency writeback topup added: $extra units of 4 KiB");
    return 1;
}

sub _state_file {
    my ($self) = @_;
    my $dir = $self->{cfg}->get('runtime', 'state_dir', '/var/lib/zram-writeback');
    return "$dir/budget.state";
}

sub _read_state {
    my ($self) = @_;
    my $file = $self->_state_file;
    my %s;
    if (open my $fh, '<', $file) {
        while (my $line = <$fh>) {
            chomp $line;
            next unless $line =~ /\A([A-Za-z0-9_]+)=(.*)\z/;
            $s{$1} = $2;
        }
        close $fh;
    }
    return \%s;
}

sub _write_state {
    my ($self, $state) = @_;
    my $file = $self->_state_file;
    my $dir = $file;
    $dir =~ s{/[^/]+\z}{};
    ensure_dir($dir, 0755) if $dir ne '' && !-d $dir;
    open my $fh, '>', $file or die "open($file): $!";
    for my $k (sort keys %$state) {
        my $v = defined $state->{$k} ? $state->{$k} : '';
        $v =~ s/\n//g;
        print {$fh} "$k=$v\n";
    }
    close $fh or die "close($file): $!";
    chmod 0644, $file;
    return 1;
}

1;
