package Zram::Command::Writeback;

use strict;
use warnings;

use Exporter qw(import);
use Zram::Error qw(fatal);
use Zram::Sysfs qw(writeback_spec);
use Zram::Types qw(validate_writeback_spec);

our @EXPORT_OK = qw(run);

sub run {
    my (@args) = @_;
    @args or fatal('usage: zram-writeback writeback-spec <spec...>');
    my $spec = join(' ', @args);
    validate_writeback_spec('writeback-spec', $spec, 0);
    writeback_spec($spec) or fatal('zram writeback sysfs trigger rejected all candidate values');
    return 0;
}

1;
