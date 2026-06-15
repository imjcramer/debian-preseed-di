package Zram::Command::Apply;

use strict;
use warnings;

use Exporter qw(import);
use Zram::Budget qw(refresh_daily_writeback_budget);
use Zram::Config qw(cfg);
use Zram::Logger qw(log_msg);
use Zram::Metrics qw(capture_zram_state);
use Zram::Sysfs qw(write_attr_optional);

our @EXPORT_OK = qw(run);

sub run {
    if (!cfg('ZRAM_WRITEBACK_ENABLED')) {
        log_msg('debug', 'skipping zram writeback apply; policy disabled');
        return 0;
    }
    my $sysfs = cfg('ZRAM_SYSFS');
    capture_zram_state('apply-before', scan_block_state => 0);
    write_attr_optional("$sysfs/writeback_batch_size", cfg('ZRAM_WRITEBACK_BATCH_SIZE'), 'zram writeback_batch_size');
    write_attr_optional("$sysfs/writeback_limit_enable", cfg('ZRAM_WRITEBACK_LIMIT_ENABLE'), 'zram writeback_limit_enable');
    refresh_daily_writeback_budget();
    capture_zram_state('apply-after', scan_block_state => 0);
    return 0;
}

1;
