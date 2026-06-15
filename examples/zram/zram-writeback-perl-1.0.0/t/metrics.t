use strict;
use warnings;
use Test::More;
use Zram::Writeback::Metrics;

my $mm = Zram::Writeback::Metrics::parse_mm_stat('4096 2048 4096 0 4096 1 2 3 4');
is($mm->{orig_data_size}, 4096, 'mm orig');
is($mm->{huge_pages_since}, 4, 'mm huge since');
is(sprintf('%.2f', Zram::Writeback::Metrics::compression_ratio($mm)), '2.00', 'ratio');
my $bd = Zram::Writeback::Metrics::parse_bd_stat('1 2 3');
is($bd->{bd_writes}, 3, 'bd writes');

done_testing;
