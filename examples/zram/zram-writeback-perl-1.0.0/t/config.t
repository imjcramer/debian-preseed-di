use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use Zram::Writeback::Config;

my ($fh, $path) = tempfile();
print {$fh} <<'INI';
[device]
name = zram1
sysfs = /tmp/zram1
require_backing_dev = false
primary_algorithm = lz4

[secondary.2]
params = level=5 ; inline comment

[pass.writeback_idle]
enabled = true
INI
close $fh;

my $cfg = Zram::Writeback::Config->new(file => $path);
is($cfg->get('device', 'name', ''), 'zram1', 'override device name');
is($cfg->get('secondary.2', 'params', ''), 'level=5', 'inline comment stripped');
is($cfg->get_bool('pass.writeback_idle', 'enabled', 0), 1, 'bool getter');
my @errors = $cfg->validate;
is_deeply(\@errors, [], 'valid config with backing requirement disabled');

unlink $path;
done_testing;
