package Zram::Config::Parser;

use strict;
use warnings;

use Exporter qw(import);
use Zram::Error qw(fatal);

our @EXPORT_OK = qw(parse_file);

use constant MAX_CONFIG_BYTES => 65_536;
use constant MAX_CONFIG_LINE_BYTES => 4_096;

sub _trim {
    my ($value) = @_;
    $value =~ s/\A\s+//;
    $value =~ s/\s+\z//;
    return $value;
}

sub _parse_value {
    my ($label, $value) = @_;
    $value = _trim($value);
    if ($value =~ /\A"(.*)"\z/s) {
        $value = $1;
        $value =~ s/\\(["\\])/$1/g;
    } elsif ($value =~ /\A'(.*)'\z/s) {
        $value = $1;
    } else {
        $value =~ s/(?:\A|\s+)[;#].*\z//;
        $value = _trim($value);
    }
    $value !~ /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/ or fatal("$label contains control characters");
    return $value;
}

sub parse_file {
    my ($path) = @_;
    open my $fh, '<', $path or fatal("missing zram-writeback config $path: $!");

    my %config;
    my $section = '';
    my $bytes = 0;
    my $line_no = 0;
    while (my $line = <$fh>) {
        $line_no++;
        $bytes += length($line);
        $bytes <= MAX_CONFIG_BYTES or fatal("zram-writeback config $path exceeds " . MAX_CONFIG_BYTES . " bytes");
        length($line) <= MAX_CONFIG_LINE_BYTES or fatal("line $line_no in $path exceeds " . MAX_CONFIG_LINE_BYTES . " bytes");
        chomp $line;
        $line =~ s/\r\z//;
        next if $line =~ /\A\s*(?:[;#]|\z)/;
        if ($line =~ /\A\s*\[([A-Za-z][A-Za-z0-9_-]*)\]\s*(?:[;#].*)?\z/) {
            $section = lc($1);
            $config{$section} ||= {};
            next;
        }
        $section ne '' or fatal("key outside any section at $path line $line_no");
        my ($key, $value) = $line =~ /\A\s*([A-Za-z][A-Za-z0-9_-]*)\s*=\s*(.*)\z/;
        defined $key or fatal("invalid INI syntax at $path line $line_no");
        $key = lc($key);
        exists $config{$section}{$key} and fatal("duplicate key [$section].$key at $path line $line_no");
        $config{$section}{$key} = _parse_value("[$section].$key", $value);
    }
    close $fh or fatal("failed to read zram-writeback config $path: $!");
    return \%config;
}

1;
