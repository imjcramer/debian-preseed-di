package Zram::Writeback::Config;

use strict;
use warnings;
use Zram::Writeback::Util qw(trim parse_bool parse_size_bytes parse_duration_seconds parse_list);

sub new {
    my ($class, %arg) = @_;
    my $self = bless {
        file => $arg{file},
        data => _defaults(),
    }, $class;
    $self->load($arg{file}) if defined $arg{file} && $arg{file} ne '';
    return $self;
}

sub load {
    my ($self, $file) = @_;
    my $parsed = parse_ini_file($file);
    _merge($self->{data}, $parsed);
    $self->{file} = $file;
    return $self;
}

sub file { return $_[0]->{file} }

sub get {
    my ($self, $section, $key, $default) = @_;
    return $default unless exists $self->{data}{$section};
    return exists $self->{data}{$section}{$key} ? $self->{data}{$section}{$key} : $default;
}

sub get_bool {
    my ($self, $section, $key, $default) = @_;
    return parse_bool($self->get($section, $key, undef), $default);
}

sub get_int {
    my ($self, $section, $key, $default) = @_;
    my $v = $self->get($section, $key, undef);
    return $default if !defined($v) || trim($v) eq '';
    die "[$section] $key must be an integer" unless $v =~ /\A-?[0-9]+\z/;
    return int($v);
}

sub get_size_bytes {
    my ($self, $section, $key, $default) = @_;
    my $v = $self->get($section, $key, undef);
    return $default if !defined($v) || trim($v) eq '';
    return parse_size_bytes($v);
}

sub get_duration_seconds {
    my ($self, $section, $key, $default) = @_;
    my $v = $self->get($section, $key, undef);
    return $default if !defined($v) || trim($v) eq '';
    return parse_duration_seconds($v);
}

sub sections {
    my ($self, $prefix) = @_;
    my @names = sort keys %{ $self->{data} };
    if (defined $prefix) {
        @names = grep { $_ eq $prefix || index($_, "$prefix.") == 0 } @names;
    }
    return @names;
}

sub section_hash {
    my ($self, $section) = @_;
    return { %{ $self->{data}{$section} || {} } };
}

sub data {
    my ($self) = @_;
    my %copy;
    for my $s (keys %{ $self->{data} }) {
        $copy{$s} = { %{ $self->{data}{$s} } };
    }
    return \%copy;
}

sub parse_ini_file {
    my ($file) = @_;
    open my $fh, '<', $file or die "open($file): $!";
    my %data;
    my $section = 'global';
    my $line_no = 0;
    while (my $line = <$fh>) {
        ++$line_no;
        chomp $line;
        $line =~ s/\r\z//;
        my $raw = trim($line);
        next if $raw eq '' || $raw =~ /\A[;#]/;
        if ($raw =~ /\A\[([^\]]+)\]\z/) {
            $section = trim($1);
            die "$file:$line_no: empty section" if $section eq '';
            $data{$section} ||= {};
            next;
        }
        my ($key, $value) = split /\s*=\s*/, $raw, 2;
        die "$file:$line_no: expected key=value" unless defined $value;
        $key = trim($key);
        $value = _strip_inline_comment(trim($value));
        $value = _unquote($value);
        die "$file:$line_no: empty key" if $key eq '';
        $data{$section}{$key} = $value;
    }
    close $fh or die "close($file): $!";
    return \%data;
}

sub _strip_inline_comment {
    my ($value) = @_;
    my $out = '';
    my $quote = '';
    my @c = split //, $value;
    for (my $i = 0; $i < @c; ++$i) {
        my $ch = $c[$i];
        if ($quote) {
            $out .= $ch;
            if ($ch eq $quote) { $quote = ''; }
            next;
        }
        if ($ch eq '"' || $ch eq "'") {
            $quote = $ch;
            $out .= $ch;
            next;
        }
        if (($ch eq ';' || $ch eq '#') && ($i == 0 || $c[$i-1] =~ /\s/)) {
            last;
        }
        $out .= $ch;
    }
    return trim($out);
}

sub _unquote {
    my ($value) = @_;
    return '' unless defined $value;
    if ($value =~ /\A"(.*)"\z/s || $value =~ /\A'(.*)'\z/s) {
        return $1;
    }
    return $value;
}

sub _merge {
    my ($base, $overlay) = @_;
    for my $s (keys %$overlay) {
        $base->{$s} ||= {};
        for my $k (keys %{ $overlay->{$s} }) {
            $base->{$s}{$k} = $overlay->{$s}{$k};
        }
    }
}

sub validate {
    my ($self) = @_;
    my @err;

    my $name = $self->get('device', 'name', '');
    push @err, '[device] name is required' if $name !~ /\Azram[0-9]+\z/;

    my $primary = $self->get('device', 'primary_algorithm', '');
    push @err, '[device] primary_algorithm is required' if $primary eq '';

    for my $section ($self->sections('secondary')) {
        next if $section eq 'secondary';
        my $prio = $self->get_int($section, 'priority', -1);
        my $algo = $self->get($section, 'algorithm', '');
        push @err, "[$section] algorithm is required" if $algo eq '';
        push @err, "[$section] priority must be 1..3" if $prio < 1 || $prio > 3;
    }

    for my $section ($self->sections('pass')) {
        next if $section eq 'pass';
        my $op = $self->get($section, 'operation', '');
        push @err, "[$section] invalid operation" unless $op =~ /\A(?:recompress|writeback)\z/;
        my $type = $self->get($section, 'type', '');
        push @err, "[$section] type is required" if $type eq '';
        if ($op eq 'recompress') {
            my $prio = $self->get_int($section, 'priority', -1);
            push @err, "[$section] priority must be 1..3 for recompress" if $prio < 1 || $prio > 3;
        }
        my @states = parse_list($self->get($section, 'run_when', ''));
        for my $state (@states) {
            push @err, "[$section] invalid run_when state: $state"
                unless $state =~ /\A(?:normal|pressure|emergency)\z/;
        }
    }

    my $backing = $self->get('device', 'backing_dev', '');
    if ($self->get_bool('device', 'require_backing_dev', 1)) {
        push @err, '[device] backing_dev must be replaced with a dedicated block partition'
            if $backing eq '' || $backing =~ /REPLACE_WITH/;
    }

    my $daily = $self->get_int('writeback_budget', 'daily_budget_mib', 0);
    push @err, '[writeback_budget] daily_budget_mib must be >= 0' if $daily < 0;

    return @err;
}

sub _defaults {
    return {
        device => {
            name                       => 'zram0',
            dev                        => '/dev/zram0',
            sysfs                      => '/sys/block/zram0',
            num_devices                => '1',
            primary_algorithm          => 'lz4',
            backing_dev                => '/dev/disk/by-partuuid/REPLACE_WITH_DEDICATED_ENCRYPTED_ZRAM_WRITEBACK_PARTITION',
            require_backing_dev        => 'true',
            compressed_writeback       => 'yes',
            writeback_batch_size       => '64',
            disksize                   => '96G',
            mem_limit                  => '48G',
            swap_priority              => '100',
            require_zswap_disabled     => 'true',
            reset_if_initialized       => 'false',
            mkswap                     => 'true',
            swapon                     => 'true',
            algorithm_param_fail_mode  => 'warn',
        },
        runtime => {
            state_dir                  => '/var/lib/zram-writeback',
            run_dir                    => '/run/zram-writeback',
            default_interval_sec       => '60',
            jitter_sec                 => '0',
            dry_run                    => 'false',
            verbose                    => 'false',
        },
        'secondary.1' => {
            algorithm                  => 'lzo-rle',
            priority                   => '1',
            purpose                    => 'idle_reusable',
            params                     => '',
        },
        'secondary.2' => {
            algorithm                  => 'zstd',
            priority                   => '2',
            purpose                    => 'huge_idle',
            params                     => 'level=6',
        },
        'secondary.3' => {
            algorithm                  => 'zstd',
            priority                   => '3',
            purpose                    => 'huge_nonidle',
            params                     => 'level=3',
        },
        idle_mark => {
            enabled                    => 'true',
            normal_idle_age_sec        => '1800',
            pressure_idle_age_sec      => '900',
            emergency_idle_age_sec     => '300',
            fallback_mark_all          => 'false',
        },
        pressure => {
            normal_mem_available_pct   => '20',
            pressure_mem_available_pct => '12',
            emergency_mem_available_pct=> '6',
            recompress_psi_some_avg10  => '0.50',
            writeback_psi_some_avg10   => '2.00',
            emergency_psi_some_avg10   => '8.00',
            writeback_psi_full_avg10   => '0.30',
            emergency_psi_full_avg10   => '1.50',
        },
        writeback_budget => {
            enabled                    => 'true',
            daily_budget_mib           => '768',
            emergency_extra_budget_mib => '1024',
            min_remaining_budget_pct   => '10',
            emergency_topup_once_daily => 'true',
        },
        'pass.idle_lzo_rle' => {
            enabled                    => 'true',
            operation                  => 'recompress',
            type                       => 'idle',
            priority                   => '1',
            threshold_bytes            => '2048',
            max_pages_normal           => '65536',
            max_pages_pressure         => '131072',
            max_pages_emergency        => '262144',
            run_when                   => 'normal,pressure,emergency',
        },
        'pass.huge_idle_zstd' => {
            enabled                    => 'true',
            operation                  => 'recompress',
            type                       => 'huge_idle',
            priority                   => '2',
            threshold_bytes            => '3000',
            max_pages_normal           => '32768',
            max_pages_pressure         => '65536',
            max_pages_emergency        => '131072',
            run_when                   => 'normal,pressure,emergency',
        },
        'pass.huge_nonidle_zstd' => {
            enabled                    => 'true',
            operation                  => 'recompress',
            type                       => 'huge',
            priority                   => '3',
            threshold_bytes            => '3584',
            max_pages_normal           => '0',
            max_pages_pressure         => '4096',
            max_pages_emergency        => '16384',
            run_when                   => 'pressure,emergency',
        },
        'pass.writeback_incompressible' => {
            enabled                    => 'true',
            operation                  => 'writeback',
            type                       => 'incompressible',
            run_when                   => 'pressure,emergency',
            requires_budget            => 'true',
            after_recompress           => 'true',
        },
        'pass.writeback_huge_idle' => {
            enabled                    => 'true',
            operation                  => 'writeback',
            type                       => 'huge_idle',
            run_when                   => 'emergency',
            requires_budget            => 'true',
            after_recompress           => 'true',
        },
        'pass.writeback_idle' => {
            enabled                    => 'false',
            operation                  => 'writeback',
            type                       => 'idle',
            run_when                   => 'emergency',
            requires_budget            => 'true',
            after_recompress           => 'true',
        },
        page_index_targeting => {
            enabled                    => 'false',
            block_state                => '/sys/kernel/debug/zram/zram0/block_state',
            max_ranges_per_write       => '128',
            max_indexes_per_pass      => '8192',
            replace_generic_writeback => 'false',
            prefer_states              => 'n,hi',
            avoid_states               => 's,w',
        },
        compact => {
            after_recompress           => 'true',
            after_writeback            => 'true',
        },
        lock => {
            lock_file                  => '/run/lock/zram-writeback-zram0.lock',
            retry_eagain               => 'true',
            retry_eagain_sleep_ms      => '250',
            retry_eagain_max           => '8',
        },
        telemetry => {
            mm_stat                    => '/sys/block/zram0/mm_stat',
            bd_stat                    => '/sys/block/zram0/bd_stat',
            io_stat                    => '/sys/block/zram0/io_stat',
            memory_psi                 => '/proc/pressure/memory',
            zsmalloc_classes           => '/sys/kernel/debug/zsmalloc/zram0/classes',
        },
    };
}

1;
