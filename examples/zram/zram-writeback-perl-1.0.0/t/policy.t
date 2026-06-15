use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile tempdir);
use Zram::Writeback::Config;
use Zram::Writeback::Policy;

{
    package FakeDevice;
    sub new { bless { calls => [], budget => 999999 }, shift }
    sub mark_idle { my ($s, $v) = @_; push @{ $s->{calls} }, "idle:$v"; 1 }
    sub recompress { my ($s, %a) = @_; push @{ $s->{calls} }, "recompress:$a{type}:$a{priority}:" . ($a{max_pages} || 0); 1 }
    sub compact { my ($s) = @_; push @{ $s->{calls} }, 'compact'; 1 }
    sub writeback_type { my ($s, $t) = @_; push @{ $s->{calls} }, "writeback:$t"; 1 }
    sub attr_exists { 1 }
    sub read_writeback_budget { $_[0]->{budget} }
    sub set_writeback_budget { my ($s, $u) = @_; $s->{budget} = $u; 1 }
}

my $dir = tempdir(CLEANUP => 1);
my ($fh, $path) = tempfile(DIR => $dir);
print {$fh} <<INI;
[device]
require_backing_dev = false
[lock]
lock_file = $dir/lock
[runtime]
state_dir = $dir
INI
close $fh;

my $cfg = Zram::Writeback::Config->new(file => $path);
my $dev = FakeDevice->new;
my $policy = Zram::Writeback::Policy->new(cfg => $cfg, device => $dev);
my $r = $policy->run_once(state_override => 'pressure');
is($r->{state}, 'pressure', 'state override');
ok((grep { $_ eq 'recompress:idle:1:131072' } @{ $dev->{calls} }), 'idle recompress pressure pass');
ok((grep { $_ eq 'recompress:huge:3:4096' } @{ $dev->{calls} }), 'huge nonidle pressure pass');
ok((grep { $_ eq 'writeback:incompressible' } @{ $dev->{calls} }), 'incompressible writeback pressure pass');

done_testing;
