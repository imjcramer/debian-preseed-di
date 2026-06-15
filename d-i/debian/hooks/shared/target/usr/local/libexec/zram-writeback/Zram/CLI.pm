package Zram::CLI;

use strict;
use warnings;

use Exporter qw(import);
use Zram;
use Zram::Command qw(dispatch requires_lock requires_sysfs);
use Zram::Config qw(load_config validate_config);
use Zram::Error qw(usage_error);
use Zram::Lock qw(acquire_lock);

our @EXPORT_OK = qw(run);

sub _usage {
    my ($exit_code) = @_;
    $exit_code = 2 if !defined $exit_code;
    print STDERR "usage: zram-writeback [--config PATH] {status|metrics|snapshot|run|daemon|writeback-spec <spec...>|apply|validate-runtime|reset-state}\n";
    return $exit_code;
}

sub run {
    my @argv = @_;
    my $config_path = $ENV{ZRAM_WRITEBACK_CONFIG} || '/etc/zram-writeback.conf';

    while (@argv && $argv[0] =~ /\A-/) {
        my $arg = shift @argv;
        if ($arg eq '--help' || $arg eq '-h') {
            return _usage(0);
        }
        if ($arg eq '--version') {
            print "zram-writeback " . Zram::version() . "\n";
            return 0;
        }
        if ($arg eq '--config') {
            @argv or usage_error('--config requires a path');
            $config_path = shift @argv;
            next;
        }
        if ($arg =~ /\A--config=(.+)\z/) {
            $config_path = $1;
            next;
        }
        usage_error("unknown option: $arg");
    }

    my $action = shift @argv;
    return _usage(2) if !defined $action || $action eq '';
    load_config($config_path);
    validate_config(require_sysfs => requires_sysfs($action));

    my $lock_fh;
    if (requires_lock($action)) {
        $lock_fh = acquire_lock();
    }
    return dispatch($action, @argv);
}

1;
