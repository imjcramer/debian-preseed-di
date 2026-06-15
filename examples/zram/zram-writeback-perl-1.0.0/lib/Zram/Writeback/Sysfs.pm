package Zram::Writeback::Sysfs;

use strict;
use warnings;
use Fcntl qw(:DEFAULT :flock);
use Errno qw(EAGAIN EINTR);
use Time::HiRes qw(sleep);
use Zram::Writeback::Util qw(log_msg trim);

sub new {
    my ($class, %arg) = @_;
    return bless {
        dry_run       => $arg{dry_run} ? 1 : 0,
        verbose       => $arg{verbose} ? 1 : 0,
        retry_eagain  => defined $arg{retry_eagain} ? $arg{retry_eagain} : 1,
        retry_sleep_s => defined $arg{retry_sleep_s} ? $arg{retry_sleep_s} : 0.25,
        retry_max     => defined $arg{retry_max} ? $arg{retry_max} : 8,
        last_error    => undef,
    }, $class;
}

sub last_error {
    my ($self) = @_;
    return $self->{last_error};
}

sub exists_path {
    my ($self, $path) = @_;
    return -e $path ? 1 : 0;
}

sub read_attr {
    my ($self, $path, %opt) = @_;
    open my $fh, '<', $path or return _fail($self, "open($path): $!", %opt);
    local $/;
    my $txt = <$fh>;
    close $fh or return _fail($self, "close($path): $!", %opt);
    $txt = '' unless defined $txt;
    chomp $txt;
    return $txt;
}

sub write_attr {
    my ($self, $path, $value, %opt) = @_;
    $value = '' unless defined $value;
    my $payload = "$value\n";

    if ($self->{dry_run}) {
        log_msg('DRYRUN', "write $path <= $value");
        return 1;
    }

    my $max = $self->{retry_eagain} ? $self->{retry_max} : 0;
    for my $attempt (0 .. $max) {
        my $ok = _write_once($path, $payload);
        if ($ok) {
            log_msg('DEBUG', "write $path <= $value") if $self->{verbose};
            $self->{last_error} = undef;
            return 1;
        }
        my $err = "$!";
        my $errno = 0 + $!;
        if (($! == EAGAIN || $! == EINTR) && $attempt < $max) {
            sleep($self->{retry_sleep_s});
            next;
        }
        return _fail($self, "write($path <= $value): $err", %opt, errno => $errno);
    }
    return _fail($self, "write($path <= $value): retry exhausted", %opt);
}

sub _write_once {
    my ($path, $payload) = @_;
    sysopen my $fh, $path, O_WRONLY or return 0;
    my $off = 0;
    while ($off < length($payload)) {
        my $n = syswrite($fh, $payload, length($payload) - $off, $off);
        return 0 unless defined $n;
        $off += $n;
    }
    close $fh or return 0;
    return 1;
}

sub wait_for_path {
    my ($self, $path, %opt) = @_;
    my $timeout = defined $opt{timeout_s} ? $opt{timeout_s} : 3;
    my $step = defined $opt{step_s} ? $opt{step_s} : 0.05;
    my $deadline = time + $timeout;
    while (time < $deadline) {
        return 1 if -e $path;
        sleep($step);
    }
    return 0;
}

sub write_attr_best_effort {
    my ($self, $path, $value, %opt) = @_;
    return 0 unless -e $path || $self->{dry_run};
    return $self->write_attr($path, $value, %opt, fatal => 0) ? 1 : 0;
}

sub _fail {
    my ($self, $msg, %opt) = @_;
    $self->{last_error} = $msg;
    die "$msg\n" if !exists($opt{fatal}) || $opt{fatal};
    return undef;
}

1;
