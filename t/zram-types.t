use strict;
use warnings;

use File::Spec;
use FindBin qw($Bin);
my $lib = "$Bin/../d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback";
use lib "$Bin/../d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback";
use Test::More;
use Zram::Types qw(validate_writeback_spec);

sub invalid_spec_exits_nonzero {
    my ($spec) = @_;
    open my $saved_stderr, '>&', \*STDERR or die "dup STDERR: $!";
    open STDERR, '>', File::Spec->devnull or die "redirect STDERR: $!";
    system(
        $^X,
        '-I',
        $lib,
        '-MZram::Types=validate_writeback_spec',
        '-e',
        'validate_writeback_spec("subprocess", $ARGV[0], 1)',
        $spec,
    );
    open STDERR, '>&', $saved_stderr or die "restore STDERR: $!";
    return $? != 0 ? 1 : 0;
}

ok(
    eval {
        validate_writeback_spec(
            'mixed page indexes',
            'page_indexes=1-100 page_indexes=200-300 page_index=42 page_index=99 page_indexes=100-200 page_indexes=500-700',
            1,
        );
        1;
    },
    'mixed single-page and LOW-HIGH page index tokens are accepted',
);

ok(invalid_spec_exits_nonzero('page_indexes=300-200'), 'descending page index ranges are rejected');

ok(invalid_spec_exits_nonzero('page=42'), 'unknown page index tokens are rejected');

done_testing;
