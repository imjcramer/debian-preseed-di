package Zram::Procfs;

use strict;
use warnings;

use Exporter qw(import);
use Zram::Config qw(cfg);
use Zram::Types qw(decimal_to_millionths);

our @EXPORT_OK = qw(
  proc_path memory_pressure_snapshot psi_avg10_millionths mem_available_bytes mem_total_bytes
);

sub proc_path {
    my (@parts) = @_;
    my $root = cfg('ZRAM_PROCFS_ROOT');
    $root =~ s{/+\z}{};
    return join '/', $root, @parts;
}

sub _read_memory_psi {
    my %psi = (some => 0, full => 0);
    open my $fh, '<', proc_path('pressure', 'memory') or return \%psi;
    while (my $line = <$fh>) {
        next if $line !~ /\A(some|full)\s/;
        my $field = $1;
        if ($line =~ /(?:\A|\s)avg10=([0-9]+(?:\.[0-9]+)?)(?:\s|\z)/) {
            $psi{$field} = decimal_to_millionths("memory PSI $field avg10", $1);
        }
    }
    close $fh;
    return \%psi;
}

sub _read_meminfo {
    my %mem = (available => 0, total => 0);
    open my $fh, '<', proc_path('meminfo') or return \%mem;
    while (my $line = <$fh>) {
        if ($line =~ /\AMemAvailable:\s+([0-9]+)\s+kB\b/) {
            $mem{available} = (0 + $1) * 1024;
        } elsif ($line =~ /\AMemTotal:\s+([0-9]+)\s+kB\b/) {
            $mem{total} = (0 + $1) * 1024;
        }
        last if $mem{available} && $mem{total};
    }
    close $fh;
    return \%mem;
}

sub memory_pressure_snapshot {
    my $mem = _read_meminfo();
    my $psi = _read_memory_psi();
    return {
        mem_available_bytes => $mem->{available},
        mem_total_bytes => $mem->{total},
        psi_some_avg10_millionths => $psi->{some},
        psi_full_avg10_millionths => $psi->{full},
    };
}

sub psi_avg10_millionths {
    my ($field) = @_;
    return _read_memory_psi()->{$field} || 0;
}

sub mem_available_bytes {
    return _read_meminfo()->{available};
}

sub mem_total_bytes {
    return _read_meminfo()->{total};
}

1;
