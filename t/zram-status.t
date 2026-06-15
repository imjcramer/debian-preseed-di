use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
use lib "$Bin/../d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback";
use Test::More;
use Zram::Config qw(load_config);
use Zram::Device qw(device_status render_status_json render_status_plain);

sub write_file {
    my ($path, $value) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} $value;
    close $fh or die "close $path: $!";
}

my $root = tempdir(CLEANUP => 1);
my $sysfs = "$root/sys";
my $debugfs = "$root/debug";
my $procfs = "$root/proc";

make_path(
    "$sysfs/block/zram0",
    "$sysfs/class/block/zram0",
    "$sysfs/class/block/zram-writeback",
    "$debugfs/zram/zram0",
    "$procfs",
);

write_file("$sysfs/block/zram0/initstate", "1\n");
write_file("$sysfs/block/zram0/disksize", "1048576\n");
write_file("$sysfs/block/zram0/mem_limit", "524288\n");
write_file("$sysfs/block/zram0/comp_algorithm", "lzo [lz4] zstd\n");
write_file("$sysfs/block/zram0/recomp_algorithm", "algo=lzo-rle priority=1\n");
write_file("$sysfs/block/zram0/writeback_limit", "4096\n");
write_file("$sysfs/block/zram0/writeback_limit_enable", "1\n");
write_file("$sysfs/block/zram0/writeback_batch_size", "512\n");
write_file("$sysfs/block/zram0/mm_stat", "4096 1024 2048 524288 8192 2 3 4 5\n");
write_file("$sysfs/block/zram0/io_stat", "1 2 3 4\n");
write_file("$sysfs/block/zram0/bd_stat", "5 6 7\n");
write_file("$sysfs/block/zram0/debug_stat", "1\n");
write_file("$sysfs/block/zram0/writeback", "\n");
write_file("$sysfs/block/zram0/recompress", "\n");
write_file("$sysfs/block/zram0/recomp_algorithm", "algo=lzo-rle priority=1\n");
write_file("$sysfs/block/zram0/algorithm_params", "\n");
write_file("$debugfs/zram/zram0/block_state", "\n");
write_file("$procfs/swaps", "Filename Type Size Used Priority\n/dev/zram0 partition 1048576 128 300\n");

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
debugfs_root = $debugfs
procfs_root = $procfs

[runtime]
dry_run = 1
INI
close $fh;

load_config($config_path);
my $status = device_status();

is($status->{device}{initstate}, '1', 'status includes zram initstate');
is($status->{swap}{active}, 1, 'status parses active swap state');
is($status->{swap}{priority}, 300, 'status parses swap priority');
is($status->{features}{writeback}, 1, 'status reports writeback feature support');
is($status->{features}{block_state}, 1, 'status reports block_state availability');
is($status->{parsed}{mm_stat}{orig_data_size}, 4096, 'status parses mm_stat fields');
is($status->{parsed}{io_stat}{failed_writes}, 2, 'status parses io_stat fields');
is($status->{parsed}{bd_stat}{bd_writes}, 7, 'status parses bd_stat fields');

my $plain = render_status_plain($status);
like($plain, qr/\A(?:.+\n)*raw\.mm_stat=4096 1024 2048 524288 8192 2 3 4 5\n/, 'plain renderer includes raw mm_stat');
like($plain, qr/(?:\A|\n)parsed\.bd_stat\.bd_writes=7\n/, 'plain renderer includes parsed bd_stat');

my $json = render_status_json($status);
like($json, qr/"swap":\{/, 'JSON renderer includes swap object');
like($json, qr/"bd_writes":7/, 'JSON renderer includes parsed bd_stat value');

unlink $config_path;
done_testing;
