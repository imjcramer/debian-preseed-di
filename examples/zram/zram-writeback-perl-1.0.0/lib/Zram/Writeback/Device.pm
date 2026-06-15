package Zram::Writeback::Device;

use strict;
use warnings;
use Zram::Writeback::Sysfs;
use Zram::Writeback::Metrics qw();
use Zram::Writeback::Util qw(log_msg run_cmd trim parse_bool parse_list);

sub new {
    my ($class, %arg) = @_;
    my $cfg = $arg{cfg} or die 'cfg is required';
    my $sysfs = $arg{sysfs} || Zram::Writeback::Sysfs->new(
        dry_run       => $arg{dry_run} || $cfg->get_bool('runtime', 'dry_run', 0),
        verbose       => $arg{verbose} || $cfg->get_bool('runtime', 'verbose', 0),
        retry_eagain  => $cfg->get_bool('lock', 'retry_eagain', 1),
        retry_sleep_s => ($cfg->get_int('lock', 'retry_eagain_sleep_ms', 250) / 1000.0),
        retry_max     => $cfg->get_int('lock', 'retry_eagain_max', 8),
    );
    return bless { cfg => $cfg, sysfs => $sysfs }, $class;
}

sub cfg { return $_[0]->{cfg} }
sub sysfs { return $_[0]->{sysfs} }

sub name { return $_[0]->{cfg}->get('device', 'name', 'zram0') }
sub dev_path { return $_[0]->{cfg}->get('device', 'dev', '/dev/zram0') }
sub sysfs_base { return $_[0]->{cfg}->get('device', 'sysfs', '/sys/block/zram0') }

sub attr_path {
    my ($self, $attr) = @_;
    return $self->sysfs_base . '/' . $attr;
}

sub attr_exists {
    my ($self, $attr) = @_;
    return $self->{sysfs}->exists_path($self->attr_path($attr));
}

sub read_attr {
    my ($self, $attr, %opt) = @_;
    return $self->{sysfs}->read_attr($self->attr_path($attr), %opt);
}

sub write_attr {
    my ($self, $attr, $value, %opt) = @_;
    return $self->{sysfs}->write_attr($self->attr_path($attr), $value, %opt);
}

sub ensure_device {
    my ($self) = @_;
    return 1 if -d $self->sysfs_base;

    my $n = $self->{cfg}->get_int('device', 'num_devices', 1);
    my $modprobe = _find_cmd('modprobe');
    run_cmd([$modprobe, 'zram', "num_devices=$n"], dry_run => $self->{sysfs}{dry_run});
    return 1 if $self->{sysfs}->wait_for_path($self->sysfs_base, timeout_s => 3);
    die 'zram device ' . $self->name . ' did not appear under /sys/block after modprobe';
}

sub initialized {
    my ($self) = @_;
    return 0 unless $self->attr_exists('disksize');
    my $size = $self->read_attr('disksize', fatal => 0);
    return defined($size) && $size =~ /\A[0-9]+\z/ && $size > 0 ? 1 : 0;
}

sub active_swap {
    my ($self) = @_;
    my $dev = $self->dev_path;
    open my $fh, '<', '/proc/swaps' or return 0;
    while (my $line = <$fh>) {
        next if $line =~ /\AFilename\s+/;
        my ($path) = split /\s+/, $line;
        if (defined($path) && $path eq $dev) {
            close $fh;
            return 1;
        }
    }
    close $fh;
    return 0;
}

sub reset {
    my ($self, %opt) = @_;
    if ($self->active_swap) {
        die $self->dev_path . ' is active swap; pass force => 1 to swapoff/reset' unless $opt{force};
        run_cmd([_find_cmd('swapoff'), $self->dev_path], dry_run => $self->{sysfs}{dry_run});
    }
    $self->write_attr('reset', 1) if $self->attr_exists('reset');
    return 1;
}

sub setup {
    my ($self, %opt) = @_;
    my $cfg = $self->{cfg};
    my @errors = $cfg->validate;
    die join("\n", @errors) . "\n" if @errors;

    $self->ensure_device;
    $self->_enforce_zswap_policy;

    if ($self->initialized) {
        if ($opt{force_reset} || $cfg->get_bool('device', 'reset_if_initialized', 0)) {
            $self->reset(force => 1);
        } else {
            die $self->name . ' is already initialized; use --force-reset or set reset_if_initialized=true';
        }
    }

    $self->_set_primary_algorithm;
    $self->_set_backing_and_writeback_preinit;
    $self->_set_secondary_algorithms;
    $self->_set_algorithm_params;
    $self->_set_initial_budget;

    my $disksize = $cfg->get('device', 'disksize', '');
    die '[device] disksize is required' if $disksize eq '';
    $self->write_attr('disksize', $disksize);

    my $mem_limit = $cfg->get('device', 'mem_limit', '');
    $self->write_attr('mem_limit', $mem_limit) if $mem_limit ne '' && $self->attr_exists('mem_limit');

    if ($cfg->get_bool('device', 'mkswap', 1)) {
        run_cmd([_find_cmd('mkswap'), '-f', $self->dev_path], dry_run => $self->{sysfs}{dry_run});
    }
    if ($cfg->get_bool('device', 'swapon', 1)) {
        my $prio = $cfg->get_int('device', 'swap_priority', 100);
        run_cmd([_find_cmd('swapon'), '--priority', $prio, $self->dev_path], dry_run => $self->{sysfs}{dry_run});
    }
    log_msg('INFO', $self->name . ' setup complete');
    return 1;
}

sub _set_primary_algorithm {
    my ($self) = @_;
    my $algo = $self->{cfg}->get('device', 'primary_algorithm', 'lz4');
    if ($self->attr_exists('comp_algorithm')) {
        $self->_require_algorithm_supported('comp_algorithm', $algo);
        $self->write_attr('comp_algorithm', $algo);
    } else {
        die 'comp_algorithm sysfs attribute is missing';
    }
}

sub _set_backing_and_writeback_preinit {
    my ($self) = @_;
    my $cfg = $self->{cfg};
    my $backing = $cfg->get('device', 'backing_dev', '');
    if ($backing ne '') {
        die "backing_dev does not exist: $backing" unless $self->{sysfs}{dry_run} || -e $backing;
        $self->write_attr('backing_dev', $backing) if $self->attr_exists('backing_dev');
    }
    my $cw = $cfg->get('device', 'compressed_writeback', '');
    $self->write_attr('compressed_writeback', $cw) if $cw ne '' && $self->attr_exists('compressed_writeback');
    my $batch = $cfg->get('device', 'writeback_batch_size', '');
    $self->write_attr('writeback_batch_size', $batch) if $batch ne '' && $self->attr_exists('writeback_batch_size');
}

sub _set_secondary_algorithms {
    my ($self) = @_;
    return unless $self->attr_exists('recomp_algorithm');
    for my $section ($self->{cfg}->sections('secondary')) {
        next if $section eq 'secondary';
        my $algo = $self->{cfg}->get($section, 'algorithm', '');
        my $prio = $self->{cfg}->get_int($section, 'priority', 0);
        next if $algo eq '' || $prio <= 0;
        $self->_require_algorithm_supported('recomp_algorithm', $algo);
        $self->write_attr('recomp_algorithm', "algo=$algo priority=$prio");
    }
}

sub _set_algorithm_params {
    my ($self) = @_;
    return unless $self->attr_exists('algorithm_params');
    my $mode = lc $self->{cfg}->get('device', 'algorithm_param_fail_mode', 'warn');
    for my $section ($self->{cfg}->sections('secondary')) {
        next if $section eq 'secondary';
        my $params = trim($self->{cfg}->get($section, 'params', ''));
        next if $params eq '';
        my $prio = $self->{cfg}->get_int($section, 'priority', 0);
        my $payload = "priority=$prio $params";
        my $ok = $self->write_attr('algorithm_params', $payload, fatal => 0);
        next if $ok;
        my $err = $self->{sysfs}->last_error || 'unknown error';
        die "algorithm_params failed for [$section]: $err\n" if $mode eq 'fail';
        log_msg('WARN', "algorithm_params ignored for [$section]: $err");
    }
}

sub _set_initial_budget {
    my ($self) = @_;
    return unless $self->{cfg}->get_bool('writeback_budget', 'enabled', 1);
    return unless $self->attr_exists('writeback_limit') && $self->attr_exists('writeback_limit_enable');
    my $mib = $self->{cfg}->get_int('writeback_budget', 'daily_budget_mib', 0);
    my $units = int($mib * 1024 * 1024 / 4096);
    $self->set_writeback_budget($units, 1);
}

sub _require_algorithm_supported {
    my ($self, $attr, $algo) = @_;
    my $txt = $self->read_attr($attr, fatal => 0);
    return 1 unless defined $txt;
    my $norm = $txt;
    $norm =~ s/[\[\]]//g;
    my %supported = map { $_ => 1 } grep { $_ ne '' && $_ !~ /\A[0-9]+:\z/ } split /\s+/, $norm;
    die "$attr does not list required algorithm '$algo': $txt" unless $supported{$algo};
    return 1;
}

sub _enforce_zswap_policy {
    my ($self) = @_;
    return unless $self->{cfg}->get_bool('device', 'require_zswap_disabled', 1);
    my $path = '/sys/module/zswap/parameters/enabled';
    return unless -e $path;
    open my $fh, '<', $path or return;
    my $v = <$fh>;
    close $fh;
    $v = lc trim($v || '');
    die 'zswap is enabled; disable it for this zram-first design' if $v =~ /\A(?:1|y|yes|true|on)\z/;
}

sub mark_idle {
    my ($self, $age_or_all) = @_;
    return 0 unless $self->attr_exists('idle');
    $self->write_attr('idle', $age_or_all);
    return 1;
}

sub recompress {
    my ($self, %arg) = @_;
    return 0 unless $self->attr_exists('recompress');
    my @kv;
    push @kv, "type=$arg{type}" if defined($arg{type}) && $arg{type} ne '';
    push @kv, "threshold=$arg{threshold}" if defined($arg{threshold}) && $arg{threshold} ne '' && $arg{threshold} > 0;
    push @kv, "priority=$arg{priority}" if defined($arg{priority}) && $arg{priority} ne '';
    push @kv, "max_pages=$arg{max_pages}" if defined($arg{max_pages}) && $arg{max_pages} ne '' && $arg{max_pages} > 0;
    die 'recompress requires priority' unless grep { /\Apriority=/ } @kv;
    $self->write_attr('recompress', join(' ', @kv));
    return 1;
}

sub writeback_type {
    my ($self, $type) = @_;
    return 0 unless $self->attr_exists('writeback');
    my $ok = $self->write_attr('writeback', "type=$type", fatal => 0);
    return 1 if $ok;
    $self->write_attr('writeback', $type);
    return 1;
}

sub writeback_page_arg {
    my ($self, $arg) = @_;
    return 0 unless $self->attr_exists('writeback');
    $self->write_attr('writeback', $arg);
    return 1;
}

sub compact {
    my ($self) = @_;
    return 0 unless $self->attr_exists('compact');
    $self->write_attr('compact', 1);
    return 1;
}

sub set_writeback_budget {
    my ($self, $units, $enable) = @_;
    return 0 unless $self->attr_exists('writeback_limit') && $self->attr_exists('writeback_limit_enable');
    $units = int($units || 0);
    $self->write_attr('writeback_limit', $units);
    $self->write_attr('writeback_limit_enable', $enable ? 1 : 0);
    return 1;
}

sub read_writeback_budget {
    my ($self) = @_;
    return undef unless $self->attr_exists('writeback_limit');
    my $v = $self->read_attr('writeback_limit', fatal => 0);
    return undef unless defined($v) && $v =~ /\A[0-9]+\z/;
    return int($v);
}

sub read_metrics {
    my ($self) = @_;
    my %m;
    if ($self->attr_exists('mm_stat')) {
        my $txt = $self->read_attr('mm_stat', fatal => 0);
        $m{mm_stat} = Zram::Writeback::Metrics::parse_mm_stat($txt) if defined $txt;
    }
    if ($self->attr_exists('bd_stat')) {
        my $txt = $self->read_attr('bd_stat', fatal => 0);
        $m{bd_stat} = Zram::Writeback::Metrics::parse_bd_stat($txt) if defined $txt;
    }
    if ($self->attr_exists('io_stat')) {
        my $txt = $self->read_attr('io_stat', fatal => 0);
        $m{io_stat} = Zram::Writeback::Metrics::parse_io_stat($txt) if defined $txt;
    }
    return \%m;
}

sub validate_kernel_surface {
    my ($self) = @_;
    my @missing;
    for my $attr (qw(comp_algorithm disksize reset mm_stat compact)) {
        push @missing, $attr unless $self->attr_exists($attr);
    }
    for my $attr (qw(recomp_algorithm recompress idle writeback writeback_limit writeback_limit_enable compressed_writeback)) {
        push @missing, $attr unless $self->attr_exists($attr);
    }
    return @missing;
}

sub _find_cmd {
    my ($name) = @_;
    for my $dir (qw(/usr/sbin /sbin /usr/bin /bin)) {
        my $p = "$dir/$name";
        return $p if -x $p;
    }
    return $name;
}

1;
