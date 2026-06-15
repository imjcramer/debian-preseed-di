use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback";
use Test::More;
use Zram::Metrics qw(capture_zram_state add_page_index_range finish_page_index_ranges new_range_builder);
use File::Path qw(make_path);
use File::Temp qw(tempdir tempfile);
use Zram::Config qw(load_config);

my $capped = new_range_builder(max_pages => 5, chunk_page_limit => 3);
for my $page (1 .. 8) {
    add_page_index_range($capped, $page);
}
is_deeply(
    [finish_page_index_ranges($capped)],
    ['page_indexes=1-3', 'page_indexes=4-5'],
    'page-index builder enforces class max pages and pages-per-spec chunks',
);
is($capped->{pages}, 8, 'builder keeps candidate count separate from emitted cap');
is($capped->{emitted_pages}, 5, 'builder emits only the capped page count');
is($capped->{capped}, 1, 'builder reports intentional cap truncation');

my $chunked = new_range_builder(chunk_page_limit => 3);
for my $page (1, 2, 10, 11, 12, 20) {
    add_page_index_range($chunked, $page);
}
is_deeply(
    [finish_page_index_ranges($chunked)],
    ['page_indexes=1-2', 'page_indexes=10-12', 'page_index=20'],
    'page-index builder keeps each sysfs writeback spec under the page limit',
);
is($chunked->{emitted_pages}, 6, 'uncapped builder emits every candidate page');

sub write_file {
    my ($path, $value) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} $value;
    close $fh or die "close $path: $!";
}

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
write_file(
    "$debugfs/zram/zram0/block_state",
    "1 1000 ih\n" .
    "2 1000 ihn\n" .
    "3 1000 ih\n" .
    "4 1000 n\n" .
    "5 1000 n\n",
);

my ($fh, $config_path) = tempfile();
print {$fh} <<"INI";
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback
idle_age_seconds = 300

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
close $fh or die "close $config_path: $!";
load_config($config_path);

my $no_writeback = capture_zram_state(
    'test-no-writeback',
    idle_age_sec => 300,
    writeback_class_caps => {},
);
is_deeply($no_writeback->{incompressible_writeback_specs}, [], 'capture skips writeback specs when no classes are requested');
is($no_writeback->{targeted_incompressible_pages}, 0, 'disabled class avoids targeted range construction');

my $capped_capture = capture_zram_state(
    'test-capped-writeback',
    idle_age_sec => 300,
    writeback_class_caps => {
        incompressible => 2,
        huge_idle => 8,
    },
);
is_deeply(
    $capped_capture->{incompressible_writeback_specs},
    ['page_index=2 page_index=4'],
    'incompressible targets include idle and non-idle incompressible pages first',
);
is($capped_capture->{emitted_incompressible_pages}, 2, 'incompressible target emission is capped by pass budget');
is_deeply(
    $capped_capture->{huge_idle_writeback_specs},
    ['page_index=1 page_index=3'],
    'huge-idle targets skip pages already covered by incompressible writeback',
);

unlink $config_path;
done_testing;
