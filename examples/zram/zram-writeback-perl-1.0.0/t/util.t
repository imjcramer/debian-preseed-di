use strict;
use warnings;
use Test::More;
use Zram::Writeback::Util qw(parse_size_bytes parse_duration_seconds parse_bool parse_list trim format_bytes);

is(trim('  x  '), 'x', 'trim');
is(parse_size_bytes('1K'), 1024, '1K');
is(parse_size_bytes('1M'), 1024 * 1024, '1M');
is(parse_size_bytes('1.5G'), int(1.5 * 1024 * 1024 * 1024), '1.5G');
is(parse_duration_seconds('2m'), 120, '2m');
is(parse_duration_seconds('1h'), 3600, '1h');
is(parse_bool('yes'), 1, 'yes');
is(parse_bool('off'), 0, 'off');
is_deeply([parse_list('a,b, c ,,')], [qw(a b c)], 'parse_list');
like(format_bytes(1536), qr/1\.50 KiB/, 'format_bytes');

done_testing;
