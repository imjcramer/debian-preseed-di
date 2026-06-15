use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
use lib "$Bin/../d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback";
use Test::More;
use Zram::Config qw(load_config);
use Zram::Metrics qw(snapshot_file);
use Zram::Policy qw(policy_plan run_maintenance);

sub write_file {
    my ($path, $value) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} $value;
    close $fh or die "close $path: $!";
}

my ($fh, $path) = tempfile();
print {$fh} <<'INI';
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback

[runtime]
dry_run = 1
INI
close $fh;
load_config($path);

my $stats = {
    block_state_available => 1,
    block_state_truncated => 0,
    idle_pages => 512,
    cold_pages => 512,
    huge_pages => 8,
    huge_idle_pages => 2,
    huge_idle_cold_pages => 2,
    incompressible_pages => 3,
    incompressible_cold_pages => 3,
    targeted_incompressible_pages => 3,
    targeted_huge_idle_pages => 2,
    incompressible_writeback_specs => ['page_indexes=10-12'],
    huge_idle_writeback_specs => ['page_indexes=20-21'],
};

my $normal = policy_plan('normal', $stats, budget_allows => 1);
is_deeply(
    $normal->{recompress},
    [
        'type=idle priority=1 threshold=2048 max_pages=65536',
        'type=huge_idle priority=2 threshold=3000 max_pages=32768',
    ],
    'normal recompresses idle and huge-idle tiers only',
);
is_deeply($normal->{writeback}, [], 'normal never writes back pages');

my $pressure = policy_plan('pressure', $stats, budget_allows => 1);
is_deeply(
    $pressure->{recompress},
    [
        'type=idle priority=1 threshold=2048 max_pages=131072',
        'type=huge_idle priority=2 threshold=3000 max_pages=65536',
        'type=huge priority=3 threshold=3584 max_pages=4096',
    ],
    'pressure adds the limited huge non-idle tier',
);
is_deeply($pressure->{writeback}, ['page_indexes=10-12'], 'pressure writes back incompressible targets only');

my $emergency = policy_plan('emergency', $stats, budget_allows => 1);
is_deeply(
    $emergency->{writeback},
    ['page_indexes=10-12', 'page_indexes=20-21'],
    'emergency writes back incompressible and huge-idle targets',
);

my $budgeted_emergency = policy_plan(
    'emergency',
    $stats,
    budget_allows => 1,
    writeback_pages_available => 4,
);
is_deeply(
    $budgeted_emergency->{writeback},
    ['page_indexes=10-12', 'page_index=20'],
    'emergency writeback trims targeted specs to fit the remaining pass budget',
);

my $partially_budgeted = policy_plan(
    'emergency',
    {
        %{$stats},
        incompressible_pages => 1,
        incompressible_cold_pages => 1,
        targeted_incompressible_pages => 1,
        incompressible_writeback_specs => ['page_index=10'],
        huge_idle_pages => 5,
        huge_idle_cold_pages => 5,
        targeted_huge_idle_pages => 5,
        huge_idle_writeback_specs => ['page_indexes=20-24'],
    },
    budget_allows => 1,
    writeback_pages_available => 5,
);
is_deeply(
    $partially_budgeted->{writeback},
    ['page_index=10', 'page_indexes=20-23'],
    'emergency writeback trims huge-idle targeted specs to the post-incompressible remaining budget',
);

my $exhausted = policy_plan('emergency', $stats, budget_allows => 0);
ok(@{$exhausted->{recompress}}, 'budget exhaustion keeps recompression work');
is_deeply($exhausted->{writeback}, [], 'budget exhaustion suppresses writeback');

my ($cap_fh, $cap_path) = tempfile();
print {$cap_fh} <<'INI';
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback

[cold_tier]
recompress_idle_max_pages = 8
recompress_huge_idle_max_pages = 4
recompress_huge_max_pages = 2
writeback_incompressible_max_pages = 16

[runtime]
dry_run = 1
INI
close $cap_fh;
load_config($cap_path);

my $capped = policy_plan('pressure', $stats, budget_allows => 1);
is_deeply(
    $capped->{recompress},
    [
        'type=idle priority=1 threshold=2048 max_pages=8',
        'type=huge_idle priority=2 threshold=3000 max_pages=4',
        'type=huge priority=3 threshold=3584 max_pages=2',
    ],
    'cold-tier recompress caps bound each recompress class independently',
);

my $non_authoritative = {
    block_state_available => 0,
    block_state_truncated => 0,
    cold_pages => 512,
    incompressible_pages => 3,
};
my $no_fallback = policy_plan('pressure', $non_authoritative, budget_allows => 1);
is_deeply(
    $no_fallback->{writeback},
    [],
    'incompressible writeback cap suppresses uncapped generic fallback without targeted page indexes',
);

my $no_huge_idle_fallback = policy_plan(
    'emergency',
    {
        block_state_available => 0,
        block_state_truncated => 0,
        cold_pages => 512,
        huge_idle_pages => 8,
    },
    budget_allows => 1,
);
is_deeply(
    $no_huge_idle_fallback->{writeback},
    [],
    'emergency huge-idle writeback requires targeted page indexes',
);

my $runtime_root = $ENV{XDG_RUNTIME_DIR} || '/run/user/1000';
my $root = tempdir(DIR => $runtime_root, CLEANUP => 1);
my $sysfs = "$root/sys";
my $debugfs = "$root/debug";
my $procfs = "$root/proc";
my $runtime_dir = "$root/run/zram";
make_path("$sysfs/block/zram0", "$debugfs/zram/zram0", $procfs, $runtime_dir);
write_file("$procfs/uptime", "10000.00 0.00\n");
write_file("$sysfs/block/zram0/disksize", "409600\n");
write_file("$sysfs/block/zram0/mm_stat", "40960 1024 2048 0 0 0 0 0 0\n");
write_file("$sysfs/block/zram0/io_stat", "0 0 0 0\n");
write_file("$sysfs/block/zram0/bd_stat", "0 0 0\n");
write_file("$sysfs/block/zram0/debug_stat", "1\n");
write_file("$debugfs/zram/zram0/block_state", ("1 1000 ihn\n" x 10));

my ($no_work_fh, $no_work_path) = tempfile();
print {$no_work_fh} <<"INI";
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback

[recompression]
enabled = 0

[cold_tier]
writeback_enabled = 0

[paths]
sysfs_root = $sysfs
debugfs_root = $debugfs
procfs_root = $procfs
runtime_dir = $runtime_dir

[runtime]
lock_file = $runtime_dir/zram-writeback.lock
log_level = none
dry_run = 1
INI
close $no_work_fh or die "close $no_work_path: $!";
load_config($no_work_path);

my $no_work = run_maintenance(state => 'pressure');
is($no_work->{operations}, 0, 'no-work maintenance exits without operations');
open my $metrics_fh, '<', snapshot_file() or die 'open metrics: ' . $!;
my $metrics = do { local $/; <$metrics_fh> };
close $metrics_fh or die 'close metrics: ' . $!;
like($metrics, qr/^phase=maintenance-pressure-no-work$/m, 'no-work maintenance records the skipped phase');
like($metrics, qr/^block_state_scanned_lines=0$/m, 'no-work maintenance avoids block_state scans');

write_file("$sysfs/block/zram0/writeback_limit", "5\n");
write_file("$sysfs/block/zram0/writeback", "\n");
write_file(
    "$debugfs/zram/zram0/block_state",
    "1 1000 ih\n" .
    "2 1000 ih\n" .
    "3 1000 ih\n" .
    "4 1000 ih\n",
);

my ($huge_only_fh, $huge_only_path) = tempfile();
print {$huge_only_fh} <<"INI";
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback
idle_age_seconds = 300

[recompression]
enabled = 0

[cold_tier]
min_zram_fill_percent = 1
min_cold_pages = 1
min_huge_idle_pages = 1

[policy]
writeback_min_remaining_pages = 1

[paths]
sysfs_root = $sysfs
debugfs_root = $debugfs
procfs_root = $procfs
runtime_dir = $runtime_dir

[runtime]
lock_file = $runtime_dir/zram-writeback.lock
log_level = none
dry_run = 1
INI
close $huge_only_fh or die "close $huge_only_path: $!";
load_config($huge_only_path);

my $huge_only = run_maintenance(state => 'emergency');
is_deeply(
    $huge_only->{writeback},
    ['page_indexes=1-4'],
    'emergency writeback budget still allows huge-idle specs when incompressible has no candidates',
);

unlink $path;
unlink $cap_path;
unlink $no_work_path;
unlink $huge_only_path;
done_testing;
