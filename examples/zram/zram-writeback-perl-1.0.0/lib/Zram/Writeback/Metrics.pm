package Zram::Writeback::Metrics;

use strict;
use warnings;
use Zram::Writeback::Util qw(trim);

my @MM_STAT_NAMES = qw(
    orig_data_size compr_data_size mem_used_total mem_limit mem_used_max
    same_pages pages_compacted huge_pages huge_pages_since
);

my @BD_STAT_NAMES = qw(bd_count bd_reads bd_writes);
my @IO_STAT_NAMES = qw(failed_reads failed_writes invalid_io notify_free);

sub parse_stat_line {
    my ($line, $names) = @_;
    $line = '' unless defined $line;
    my @v = split /\s+/, trim($line);
    my %out;
    for my $i (0 .. $#v) {
        my $name = $names && defined $names->[$i] ? $names->[$i] : "field_$i";
        $out{$name} = $v[$i] =~ /\A-?[0-9]+\z/ ? int($v[$i]) : $v[$i];
    }
    return \%out;
}

sub parse_mm_stat { return parse_stat_line($_[0], \@MM_STAT_NAMES) }
sub parse_bd_stat { return parse_stat_line($_[0], \@BD_STAT_NAMES) }
sub parse_io_stat { return parse_stat_line($_[0], \@IO_STAT_NAMES) }

sub compression_ratio {
    my ($mm) = @_;
    return undef unless $mm && $mm->{compr_data_size} && $mm->{compr_data_size} > 0;
    return $mm->{orig_data_size} / $mm->{compr_data_size};
}

sub allocator_overhead_ratio {
    my ($mm) = @_;
    return undef unless $mm && $mm->{compr_data_size} && $mm->{compr_data_size} > 0;
    return $mm->{mem_used_total} / $mm->{compr_data_size};
}

1;
