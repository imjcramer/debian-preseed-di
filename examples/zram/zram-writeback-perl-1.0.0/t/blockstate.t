use strict;
use warnings;
use Test::More;
use Zram::Writeback::BlockState;

my $records = Zram::Writeback::BlockState::parse_text("300 75.033841 .wh...\n301 63.806904 s.....\n302 63.806919 ..hi..\n304 146.781902 ..hi.n\n");
is(scalar(@$records), 4, 'records parsed');
ok($records->[2]{flag}{h} && $records->[2]{flag}{i}, 'huge idle flags');
my $idx = Zram::Writeback::BlockState::select_indexes($records, prefer => [qw(n hi)], avoid => [qw(s w)]);
is_deeply($idx, [302, 304], 'selected indexes');
my $ranges = Zram::Writeback::BlockState::indexes_to_ranges([1,2,3,7,9,10], 10);
is(Zram::Writeback::BlockState::ranges_to_writeback_arg($ranges), 'page_indexes=1-3 page_index=7 page_indexes=9-10', 'range args');

done_testing;
