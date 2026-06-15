use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
use lib "$Bin/../d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback";
use Test::More;
use Zram::Config qw(load_config);
use Zram::Pressure qw(determine_pressure_state);

my $proc = tempdir(CLEANUP => 1);
make_path("$proc/pressure");

my ($fh, $path) = tempfile();
print {$fh} <<"INI";
[paths]
procfs_root = $proc

[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback

[policy]
pressure_mem_available_percent = 12
emergency_mem_available_percent = 6
memory_some_avg10_min = 0.50
memory_full_avg10_min = 0.30
emergency_some_avg10_min = 8.00
emergency_full_avg10_min = 1.50
INI
close $fh;
load_config($path);

sub write_pressure_sample {
    my (%arg) = @_;
    open my $mem, '>', "$proc/meminfo" or die "meminfo: $!";
    print {$mem} "MemTotal:       1000000 kB\n";
    print {$mem} "MemAvailable:   $arg{available_kb} kB\n";
    close $mem or die "meminfo close: $!";
    open my $psi, '>', "$proc/pressure/memory" or die "psi: $!";
    print {$psi} "some avg10=$arg{some} avg60=0.00 avg300=0.00 total=0\n";
    print {$psi} "full avg10=$arg{full} avg60=0.00 avg300=0.00 total=0\n";
    close $psi or die "psi close: $!";
}

write_pressure_sample(available_kb => 500000, some => '0.00', full => '0.00');
my ($state) = determine_pressure_state();
is($state, 'normal', 'ample memory and no PSI is normal');

write_pressure_sample(available_kb => 100000, some => '0.10', full => '0.00');
($state) = determine_pressure_state();
is($state, 'pressure', 'low MemAvailable enters pressure state');

write_pressure_sample(available_kb => 200000, some => '8.50', full => '0.00');
($state) = determine_pressure_state();
is($state, 'emergency', 'emergency PSI threshold enters emergency state');

unlink $path;
done_testing;
