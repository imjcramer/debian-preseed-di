package Zram::Writeback::Util;

use strict;
use warnings;
use Exporter 'import';
use POSIX qw(strftime);
use Time::HiRes qw(sleep time);

our @EXPORT_OK = qw(
    trim parse_bool parse_size_bytes parse_duration_seconds parse_list
    format_bytes log_msg run_cmd now_date monotonic read_text write_text
    ensure_dir min max
);

sub trim {
    my ($s) = @_;
    return '' unless defined $s;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

sub parse_bool {
    my ($v, $default) = @_;
    return $default if !defined($v) || trim($v) eq '';
    my $s = lc trim($v);
    return 1 if $s =~ /\A(?:1|yes|y|true|on|enable|enabled)\z/;
    return 0 if $s =~ /\A(?:0|no|n|false|off|disable|disabled)\z/;
    die "invalid boolean value: $v";
}

sub parse_size_bytes {
    my ($v) = @_;
    die "undefined size" unless defined $v;
    my $s = trim($v);
    die "empty size" if $s eq '';

    return int($1) if $s =~ /\A([0-9]+)\z/;
    if ($s =~ /\A([0-9]+(?:\.[0-9]+)?)\s*([kmgtp])(?:i?b)?\z/i) {
        my ($num, $unit) = ($1, lc $2);
        my %shift = ( k => 10, m => 20, g => 30, t => 40, p => 50 );
        return int($num * (2 ** $shift{$unit}));
    }
    if ($s =~ /\A([0-9]+(?:\.[0-9]+)?)\s*b\z/i) {
        return int($1);
    }
    die "invalid size value: $v";
}

sub parse_duration_seconds {
    my ($v) = @_;
    die "undefined duration" unless defined $v;
    my $s = trim($v);
    die "empty duration" if $s eq '';
    return int($s) if $s =~ /\A[0-9]+\z/;
    if ($s =~ /\A([0-9]+(?:\.[0-9]+)?)\s*([smhd])\z/i) {
        my ($num, $unit) = ($1, lc $2);
        my %mul = ( s => 1, m => 60, h => 3600, d => 86400 );
        return int($num * $mul{$unit});
    }
    die "invalid duration value: $v";
}

sub parse_list {
    my ($v) = @_;
    return () unless defined $v;
    my @out;
    for my $p (split /,/, $v) {
        $p = trim($p);
        push @out, $p if $p ne '';
    }
    return @out;
}

sub format_bytes {
    my ($bytes) = @_;
    $bytes = 0 unless defined $bytes;
    my @units = qw(B KiB MiB GiB TiB PiB);
    my $n = $bytes + 0;
    my $i = 0;
    while ($n >= 1024 && $i < $#units) {
        $n /= 1024;
        ++$i;
    }
    return $i == 0 ? sprintf('%d %s', $n, $units[$i]) : sprintf('%.2f %s', $n, $units[$i]);
}

sub log_msg {
    my ($level, $msg) = @_;
    $level = defined($level) ? uc($level) : 'INFO';
    $msg = '' unless defined $msg;
    my $ts = strftime('%Y-%m-%dT%H:%M:%S%z', localtime);
    print STDERR "$ts [$level] $msg\n";
}

sub run_cmd {
    my ($argv, %opt) = @_;
    die "run_cmd expects ARRAY ref" unless ref($argv) eq 'ARRAY' && @$argv;
    if ($opt{dry_run}) {
        log_msg('DRYRUN', join(' ', map { _quote_arg($_) } @$argv));
        return 0;
    }
    system { $argv->[0] } @$argv;
    my $rc = $?;
    if ($rc == -1) {
        die "exec $argv->[0] failed: $!";
    }
    if ($rc & 127) {
        die sprintf('command %s died with signal %d', $argv->[0], ($rc & 127));
    }
    my $exit = $rc >> 8;
    if ($exit != 0 && !$opt{allow_fail}) {
        die sprintf('command %s exited with status %d', $argv->[0], $exit);
    }
    return $exit;
}

sub _quote_arg {
    my ($s) = @_;
    return "''" if !defined($s) || $s eq '';
    return $s if $s =~ /\A[0-9A-Za-z_:\/\.\-+=,@%]+\z/;
    $s =~ s/'/'\\''/g;
    return "'$s'";
}

sub now_date {
    return strftime('%Y-%m-%d', localtime);
}

sub monotonic {
    return time();
}

sub ensure_dir {
    my ($dir, $mode) = @_;
    $mode = 0755 unless defined $mode;
    return 1 if -d $dir;
    my @parts = split m{/+}, $dir;
    my $path = $dir =~ m{\A/} ? '/' : '';
    for my $p (@parts) {
        next if $p eq '';
        $path .= '/' if $path ne '' && $path !~ m{/$};
        $path .= $p;
        next if -d $path;
        mkdir $path, $mode or die "mkdir($path): $!";
    }
    return 1;
}

sub read_text {
    my ($path) = @_;
    open my $fh, '<', $path or die "open($path): $!";
    local $/;
    my $txt = <$fh>;
    close $fh or die "close($path): $!";
    return defined($txt) ? $txt : '';
}

sub write_text {
    my ($path, $txt, $mode) = @_;
    $mode = 0644 unless defined $mode;
    open my $fh, '>', $path or die "open($path): $!";
    print {$fh} $txt;
    close $fh or die "close($path): $!";
    chmod $mode, $path or die "chmod($path): $!";
    return 1;
}

sub min { return $_[0] < $_[1] ? $_[0] : $_[1] }
sub max { return $_[0] > $_[1] ? $_[0] : $_[1] }

1;
