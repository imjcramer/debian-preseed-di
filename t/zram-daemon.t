use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
my $lib = "$Bin/../d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback";
use lib "$Bin/../d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback";
use Test::More;
use Zram::Command qw(dispatch requires_lock requires_sysfs);
use Zram::Config qw(load_config validate_config);

sub write_file {
    my ($path, $value) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} $value;
    close $fh or die "close $path: $!";
}

sub invalid_config_exits_nonzero {
    my ($config_path) = @_;
    open my $saved_stderr, '>&', \*STDERR or die "dup STDERR: $!";
    open STDERR, '>', File::Spec->devnull or die "redirect STDERR: $!";
    system(
        $^X,
        '-I',
        $lib,
        '-MZram::Config=load_config',
        '-e',
        'load_config($ARGV[0])',
        $config_path,
    );
    open STDERR, '>&', $saved_stderr or die "restore STDERR: $!";
    return $? != 0 ? 1 : 0;
}

ok(!requires_lock('daemon'), 'daemon does not hold the lifecycle lock for its full service lifetime');
ok(requires_sysfs('daemon'), 'daemon validates zram sysfs at startup');

my $runtime_root = $ENV{XDG_RUNTIME_DIR} || '/run/user/1000';
my $root = tempdir(DIR => $runtime_root, CLEANUP => 1);
my $sysfs_root = "$root/sys";
my $procfs_root = "$root/proc";
my $runtime_dir = "$root/run/zram";
make_path("$sysfs_root/block/zram0", "$procfs_root/pressure", $runtime_dir);
write_file("$procfs_root/pressure/memory", "some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n");

my ($disabled_fh, $disabled_path) = tempfile();
print {$disabled_fh} <<"INI";
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback

[daemon]
enabled = 0
psi_some_stall_us = 150000
psi_full_stall_us = 50000

[paths]
sysfs_root = $sysfs_root
debugfs_root = $root/debug
procfs_root = $procfs_root
runtime_dir = $runtime_dir

[runtime]
lock_file = $runtime_dir/zram-writeback.lock
log_level = none
dry_run = 1
INI
close $disabled_fh or die "close $disabled_path: $!";

load_config($disabled_path);
ok(eval { validate_config(require_sysfs => requires_sysfs('daemon')); 1 }, 'disabled daemon config still validates');
is(dispatch('daemon'), 0, 'disabled daemon command exits immediately');

my ($invalid_fh, $invalid_path) = tempfile();
print {$invalid_fh} <<'INI';
[zram]
device = /dev/zram0
device_name = zram0

[writeback]
backing_dev = /dev/mapper/zram-writeback
raw_backing_dev = /dev/nvme0n1p12
backing_mapper = zram-writeback

[daemon]
enabled = 1
psi_some_stall_us = 0
psi_full_stall_us = 0
INI
close $invalid_fh or die "close $invalid_path: $!";

ok(invalid_config_exits_nonzero($invalid_path), 'enabled daemon requires at least one positive PSI trigger threshold');

my ($unknown_key_fh, $unknown_key_path) = tempfile();
print {$unknown_key_fh} <<'INI';
[zram]
unexpected = 1
INI
close $unknown_key_fh or die "close $unknown_key_path: $!";

ok(invalid_config_exits_nonzero($unknown_key_path), 'unknown zram config keys are rejected');

my ($unknown_section_fh, $unknown_section_path) = tempfile();
print {$unknown_section_fh} <<'INI';
[unknown]
enabled = 1
INI
close $unknown_section_fh or die "close $unknown_section_path: $!";

ok(invalid_config_exits_nonzero($unknown_section_path), 'unknown zram config sections are rejected');

unlink $disabled_path;
unlink $invalid_path;
unlink $unknown_key_path;
unlink $unknown_section_path;
done_testing;
