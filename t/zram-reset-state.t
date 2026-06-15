use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
use lib "$Bin/../d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback";
use Test::More;
use Zram::Command::Reset qw(run);
use Zram::Config qw(load_config);
use Zram::Metrics qw(snapshot_file);

sub write_file {
    my ($path, $value) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} $value;
    close $fh or die "close $path: $!";
}

my $runtime_root = $ENV{XDG_RUNTIME_DIR} || '/run/user/1000';
my $root = tempdir(DIR => $runtime_root, CLEANUP => 1);
my $runtime_dir = "$root/run/zram";
my $sysfs = "$root/sys";
make_path($runtime_dir, "$sysfs/block/zram0");

my ($fh, $config_path) = tempfile();
print {$fh} <<"INI";
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback

[paths]
sysfs_root = $sysfs
debugfs_root = $root/debug
procfs_root = $root/proc
runtime_dir = $runtime_dir

[runtime]
lock_file = $runtime_dir/zram-writeback.lock
log_level = none
dry_run = 1
INI
close $fh or die "close $config_path: $!";

load_config($config_path);

my $metrics_path = snapshot_file();
my $budget_path = "$runtime_dir/writeback-budget.state";
my $snapshot_path = "$runtime_dir/manual.snapshot";
my $state_path = "$runtime_dir/manual.state";
my $other_path = "$runtime_dir/keep.txt";
my $dir_path = "$runtime_dir/persist.d";

write_file($metrics_path, "phase=test\n");
write_file($budget_path, "daily_budget_date=2026-06-01\n");
write_file($snapshot_path, "snapshot\n");
write_file($state_path, "state\n");
write_file($other_path, "keep\n");
make_path($dir_path);

is(run(), 0, 'reset-state command succeeds');

ok(!-e $metrics_path, 'reset-state removes metrics file');
ok(!-e $budget_path, 'reset-state removes budget state file');
ok(!-e $snapshot_path, 'reset-state removes snapshot file');
ok(!-e $state_path, 'reset-state removes generic state file');
ok(-e $other_path, 'reset-state keeps unrelated runtime file');
ok(-d $dir_path, 'reset-state keeps directories');

unlink $config_path;
done_testing;
