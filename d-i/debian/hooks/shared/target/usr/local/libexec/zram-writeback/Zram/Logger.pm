package Zram::Logger;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(canonical_log_level set_active_log_level log_enabled log_msg);

my %LOG_LEVEL_VALUE = (
    debug   => 10,
    info    => 20,
    warning => 30,
    error   => 40,
    none    => 99,
);

my $ACTIVE_LOG_LEVEL = canonical_log_level($ENV{ZRAM_LOG_LEVEL} // 'error');
my $LOGGER;

sub canonical_log_level {
    my ($level) = @_;
    $level = lc($level // 'error');
    return 'warning' if $level eq 'warn';
    return 'error' if $level eq 'fatal';
    return exists $LOG_LEVEL_VALUE{$level} ? $level : 'error';
}

sub set_active_log_level {
    my ($level) = @_;
    $level = canonical_log_level($level);
    exists $LOG_LEVEL_VALUE{$level} or $level = 'error';
    $ACTIVE_LOG_LEVEL = $level;
}

sub log_enabled {
    my ($level) = @_;
    my $requested = canonical_log_level($level);
    return 1 if $requested eq 'error';
    return 0 if $ACTIVE_LOG_LEVEL eq 'none';
    return $LOG_LEVEL_VALUE{$requested} >= $LOG_LEVEL_VALUE{$ACTIVE_LOG_LEVEL};
}

sub _find_command {
    my ($name) = @_;
    for my $dir (split /:/, $ENV{PATH} || '') {
        return "$dir/$name" if -x "$dir/$name";
    }
    return '';
}

sub _logger_command {
    return $LOGGER if defined $LOGGER;
    $LOGGER = _find_command('logger');
    return $LOGGER;
}

sub log_msg {
    my ($level, $message) = @_;
    $level = canonical_log_level($level);
    return if !log_enabled($level);
    my $line = "$level: $message";
    print STDERR "$line\n";
    my $logger = _logger_command();
    system($logger, '-t', 'zram-writeback', '--', $line) if $logger ne '';
}

1;
