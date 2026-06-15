package Zram::Daemon;

use strict;
use warnings;

use Exporter qw(import);
use IO::Handle qw();
use IO::Poll qw(POLLERR POLLHUP POLLPRI);
use Time::HiRes qw(time);
use Zram::Config qw(cfg);
use Zram::Error qw(fatal);
use Zram::Lock qw(try_acquire_lock);
use Zram::Logger qw(log_msg);
use Zram::Policy qw(run_maintenance);
use Zram::Pressure qw(determine_pressure_state);
use Zram::Procfs qw(proc_path);

our @EXPORT_OK = qw(run_daemon);

sub _register_psi_trigger {
    my ($path, $kind, $stall_us, $window_us) = @_;
    return if $stall_us <= 0;

    open my $fh, '+<', $path or fatal("failed to open PSI trigger path $path: $!");
    my $trigger = "$kind $stall_us $window_us\n";
    if (!print {$fh} $trigger) {
        my $error = $!;
        close $fh;
        fatal("failed to register PSI $kind trigger at $path: $error");
    }
    $fh->flush or fatal("failed to flush PSI $kind trigger at $path: $!");
    return {
        fh => $fh,
        kind => $kind,
        stall_us => $stall_us,
        window_us => $window_us,
    };
}

sub _register_triggers {
    my $path = proc_path('pressure', 'memory');
    my $window_us = cfg('ZRAM_DAEMON_PSI_WINDOW_US');
    my @triggers;

    push @triggers, _register_psi_trigger($path, 'some', cfg('ZRAM_DAEMON_PSI_SOME_STALL_US'), $window_us);
    push @triggers, _register_psi_trigger($path, 'full', cfg('ZRAM_DAEMON_PSI_FULL_STALL_US'), $window_us);
    @triggers = grep { defined $_ } @triggers;
    @triggers or fatal('zram PSI daemon requires at least one enabled memory pressure trigger');
    return @triggers;
}

sub _poll_triggers {
    my ($poll, $timeout_sec) = @_;
    my $timeout_ms = int($timeout_sec * 1000);
    $timeout_ms = 1 if $timeout_ms < 1;
    my $ready = $poll->poll($timeout_ms);
    return $ready > 0 ? 1 : 0;
}

sub _cooldown_seconds {
    my ($state) = @_;
    return cfg('ZRAM_DAEMON_EMERGENCY_COOLDOWN_SEC') if $state eq 'emergency';
    return cfg('ZRAM_DAEMON_PRESSURE_COOLDOWN_SEC');
}

sub _state_rank {
    my ($state) = @_;
    return 2 if $state eq 'emergency';
    return 1 if $state eq 'pressure';
    return 0;
}

sub _should_run_pass {
    my ($state, $now, $last_pass_at, $last_state) = @_;
    return 0 if $state eq 'normal';
    my $cooldown = _cooldown_seconds($state);
    return 1 if !defined $last_pass_at;
    return 1 if _state_rank($state) > _state_rank($last_state || 'normal');
    return ($now - $last_pass_at) >= $cooldown ? 1 : 0;
}

sub _run_pressure_pass {
    my ($state) = @_;
    my $lock_fh = try_acquire_lock();
    if (!defined $lock_fh) {
        log_msg('debug', "zram PSI daemon skipped $state pass because another pass is active");
        return undef;
    }
    run_maintenance(state => $state);
    return 1;
}

sub run_daemon {
    return 0 if !cfg('ZRAM_DAEMON_ENABLED');
    return 0 if !cfg('ZRAM_PRESSURE_ENABLED');

    my @triggers = _register_triggers();
    my $poll = IO::Poll->new();
    for my $trigger (@triggers) {
        $poll->mask($trigger->{fh} => POLLPRI | POLLERR | POLLHUP);
        log_msg(
            'info',
            "registered zram PSI $trigger->{kind} trigger " .
            "stall_us=$trigger->{stall_us} window_us=$trigger->{window_us}"
        );
    }

    my $stop = 0;
    local $SIG{TERM} = sub { $stop = 1; };
    local $SIG{INT} = sub { $stop = 1; };

    my $last_state = 'normal';
    my $last_pass_at;
    my $normal_since = time;
    my $recovery_hysteresis = cfg('ZRAM_DAEMON_RECOVERY_HYSTERESIS_SEC');
    my $poll_timeout = cfg('ZRAM_DAEMON_POLL_TIMEOUT_SEC');

    log_msg('info', 'zram PSI daemon started');
    while (!$stop) {
        my $event = _poll_triggers($poll, $poll_timeout);
        next if !$event || $stop;

        my $now = time;
        my ($state, $reasons) = determine_pressure_state();
        if ($state eq 'normal') {
            $normal_since = $now if !defined $normal_since;
            if ($last_state ne 'normal' && ($now - $normal_since) >= $recovery_hysteresis) {
                log_msg('info', 'zram PSI daemon recovered to normal pressure state');
                $last_state = 'normal';
            } else {
                log_msg('debug', 'zram PSI daemon ignored event below pressure thresholds');
            }
            next;
        }

        $normal_since = undef;
        if (!_should_run_pass($state, $now, $last_pass_at, $last_state)) {
            log_msg(
                'debug',
                'zram PSI daemon suppressed ' . $state .
                ' pass inside cooldown reason=' . join('; ', @{$reasons || []})
            );
            next;
        }

        log_msg('info', 'zram PSI daemon dispatching ' . $state . ' pass reason=' . join('; ', @{$reasons || []}));
        my $pass_ran = _run_pressure_pass($state);
        if (defined $pass_ran) {
            $last_pass_at = $now;
            $last_state = $state;
        }
    }
    log_msg('info', 'zram PSI daemon stopped');
    return 0;
}

1;
