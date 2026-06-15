package Zram::Writeback::BlockState;

use strict;
use warnings;
use Zram::Writeback::Util qw(parse_list);

sub parse_line {
    my ($line) = @_;
    return undef unless defined $line;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    return undef unless $line =~ /\A([0-9]+)\s+([0-9.]+)\s+([.A-Za-z]+)\z/;
    my ($idx, $age, $flags) = (int($1), $2 + 0, $3);
    my %f;
    for my $ch (split //, $flags) {
        next if $ch eq '.';
        $f{$ch} = 1;
    }
    return { index => $idx, age => $age, flags => $flags, flag => \%f };
}

sub parse_text {
    my ($text) = @_;
    my @records;
    for my $line (split /\n/, $text || '') {
        my $r = parse_line($line);
        push @records, $r if $r;
    }
    return \@records;
}

sub read_file {
    my ($path, $max_records) = @_;
    open my $fh, '<', $path or die "open($path): $!";
    my @records;
    while (my $line = <$fh>) {
        my $r = parse_line($line);
        push @records, $r if $r;
        last if defined($max_records) && @records >= $max_records;
    }
    close $fh or die "close($path): $!";
    return \@records;
}

sub select_indexes {
    my ($records, %opt) = @_;
    my @prefer = ref($opt{prefer}) eq 'ARRAY' ? @{ $opt{prefer} } : parse_list($opt{prefer} || '');
    my @avoid  = ref($opt{avoid})  eq 'ARRAY' ? @{ $opt{avoid} }  : parse_list($opt{avoid} || '');
    my $max = $opt{max} || 0;
    my @idx;

    RECORD:
    for my $r (@$records) {
        for my $avoid (@avoid) {
            next RECORD if _matches_state($r, $avoid);
        }
        if (@prefer) {
            my $hit = 0;
            for my $want (@prefer) {
                if (_matches_state($r, $want)) { $hit = 1; last; }
            }
            next RECORD unless $hit;
        }
        push @idx, $r->{index};
        last if $max && @idx >= $max;
    }
    return \@idx;
}

sub indexes_to_ranges {
    my ($indexes, $max_ranges) = @_;
    my @i = sort { $a <=> $b } @$indexes;
    my @ranges;
    my ($start, $prev);
    for my $idx (@i) {
        if (!defined $start) {
            ($start, $prev) = ($idx, $idx);
            next;
        }
        if ($idx == $prev + 1) {
            $prev = $idx;
            next;
        }
        push @ranges, [$start, $prev];
        last if $max_ranges && @ranges >= $max_ranges;
        ($start, $prev) = ($idx, $idx);
    }
    push @ranges, [$start, $prev] if defined($start) && (!$max_ranges || @ranges < $max_ranges);
    return \@ranges;
}

sub ranges_to_writeback_arg {
    my ($ranges) = @_;
    return join ' ', map {
        $_->[0] == $_->[1] ? "page_index=$_->[0]" : "page_indexes=$_->[0]-$_->[1]"
    } @$ranges;
}

sub _matches_state {
    my ($r, $state) = @_;
    return 0 unless defined $state && $state ne '';
    if ($state eq 'hi') {
        return $r->{flag}{h} && $r->{flag}{i} ? 1 : 0;
    }
    for my $ch (split //, $state) {
        next if $ch eq '.' || $ch eq ',';
        return 0 unless $r->{flag}{$ch};
    }
    return 1;
}

1;
