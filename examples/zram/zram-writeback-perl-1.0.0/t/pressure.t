use strict;
use warnings;
use Test::More;
use Zram::Writeback::Config;
use Zram::Writeback::Pressure;

my $mem = Zram::Writeback::Pressure::parse_meminfo("MemTotal: 1000000 kB\nMemAvailable: 50000 kB\n");
is(int(Zram::Writeback::Pressure::mem_available_pct($mem)), 5, 'mem available percent');

my $psi = Zram::Writeback::Pressure::parse_psi("some avg10=9.00 avg60=1.00 avg300=0.20 total=99\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n");
is($psi->{some}{avg10}, 9.00, 'psi some avg10');

my $cfg = Zram::Writeback::Config->new;
my $p = Zram::Writeback::Pressure->new(cfg => $cfg);
my ($state) = $p->determine_state({ meminfo => $mem, psi => $psi });
is($state, 'emergency', 'emergency state');

done_testing;
