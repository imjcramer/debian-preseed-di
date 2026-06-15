use strict;
use warnings;
use Test::More;

use_ok('Zram::Writeback');
use_ok('Zram::Writeback::Util');
use_ok('Zram::Writeback::Config');
use_ok('Zram::Writeback::Sysfs');
use_ok('Zram::Writeback::Metrics');
use_ok('Zram::Writeback::Pressure');
use_ok('Zram::Writeback::Budget');
use_ok('Zram::Writeback::Lock');
use_ok('Zram::Writeback::Device');
use_ok('Zram::Writeback::Policy');
use_ok('Zram::Writeback::BlockState');

done_testing;
