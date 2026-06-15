package Zram::Writeback::Pressure;

use strict;
use warnings;
use Zram::Writeback::Util qw(trim);

sub new {
    my ($class, %arg) = @_;
    return bless { cfg => $arg{cfg} }, $class;
}

sub read_meminfo {
    my ($self, $path) = @_;
    $path ||= '/proc/meminfo';
    open my $fh, '<', $path or return {};
    local $/;
    my $txt = <$fh>;
    close $fh;
    return parse_meminfo($txt);
}

sub parse_meminfo {
    my ($txt) = @_;
    my %m;
    for my $line (split /\n/, $txt || '') {
        next unless $line =~ /\A([^:]+):\s+([0-9]+)\s*(\S+)?/;
        my ($key, $val, $unit) = ($1, $2, $3 || '');
        $m{$key} = lc($unit) eq 'kb' ? int($val) * 1024 : int($val);
    }
    return \%m;
}

sub read_psi {
    my ($self, $path) = @_;
    $path ||= '/proc/pressure/memory';
    open my $fh, '<', $path or return {};
    local $/;
    my $txt = <$fh>;
    close $fh;
    return parse_psi($txt);
}

sub parse_psi {
    my ($txt) = @_;
    my %out;
    for my $line (split /\n/, $txt || '') {
        $line = trim($line);
        next if $line eq '';
        my ($kind, @pairs) = split /\s+/, $line;
        next unless defined $kind && ($kind eq 'some' || $kind eq 'full');
        for my $p (@pairs) {
            my ($k, $v) = split /=/, $p, 2;
            next unless defined $k && defined $v;
            $out{$kind}{$k} = $v + 0;
        }
    }
    return \%out;
}

sub sample {
    my ($self) = @_;
    my $cfg = $self->{cfg};
    my $psi_path = $cfg ? $cfg->get('telemetry', 'memory_psi', '/proc/pressure/memory') : '/proc/pressure/memory';
    my $mem = $self->read_meminfo('/proc/meminfo');
    my $psi = $self->read_psi($psi_path);
    return { meminfo => $mem, psi => $psi };
}

sub mem_available_pct {
    my ($mem) = @_;
    return undef unless $mem && $mem->{MemTotal} && $mem->{MemAvailable};
    return ($mem->{MemAvailable} * 100.0) / $mem->{MemTotal};
}

sub determine_state {
    my ($self, $sample) = @_;
    $sample ||= $self->sample;
    my $cfg = $self->{cfg};
    my $mem_pct = mem_available_pct($sample->{meminfo});
    my $some10 = $sample->{psi}{some}{avg10} || 0;
    my $full10 = $sample->{psi}{full}{avg10} || 0;

    my $pressure_mem = $cfg ? $cfg->get('pressure', 'pressure_mem_available_pct', 12) + 0 : 12;
    my $emerg_mem    = $cfg ? $cfg->get('pressure', 'emergency_mem_available_pct', 6) + 0 : 6;
    my $recomp_some  = $cfg ? $cfg->get('pressure', 'recompress_psi_some_avg10', 0.50) + 0 : 0.50;
    my $wb_some      = $cfg ? $cfg->get('pressure', 'writeback_psi_some_avg10', 2.00) + 0 : 2.00;
    my $emerg_some   = $cfg ? $cfg->get('pressure', 'emergency_psi_some_avg10', 8.00) + 0 : 8.00;
    my $wb_full      = $cfg ? $cfg->get('pressure', 'writeback_psi_full_avg10', 0.30) + 0 : 0.30;
    my $emerg_full   = $cfg ? $cfg->get('pressure', 'emergency_psi_full_avg10', 1.50) + 0 : 1.50;

    my @reasons;
    if ((defined($mem_pct) && $mem_pct <= $emerg_mem) || $some10 >= $emerg_some || $full10 >= $emerg_full) {
        push @reasons, sprintf('MemAvailable=%.2f%%<=%.2f%%', $mem_pct, $emerg_mem) if defined($mem_pct) && $mem_pct <= $emerg_mem;
        push @reasons, sprintf('PSI some avg10=%.2f>=%.2f', $some10, $emerg_some) if $some10 >= $emerg_some;
        push @reasons, sprintf('PSI full avg10=%.2f>=%.2f', $full10, $emerg_full) if $full10 >= $emerg_full;
        return ('emergency', \@reasons, $sample);
    }

    if ((defined($mem_pct) && $mem_pct <= $pressure_mem) || $some10 >= $recomp_some || $some10 >= $wb_some || $full10 >= $wb_full) {
        push @reasons, sprintf('MemAvailable=%.2f%%<=%.2f%%', $mem_pct, $pressure_mem) if defined($mem_pct) && $mem_pct <= $pressure_mem;
        push @reasons, sprintf('PSI some avg10=%.2f>=%.2f', $some10, $recomp_some) if $some10 >= $recomp_some;
        push @reasons, sprintf('PSI full avg10=%.2f>=%.2f', $full10, $wb_full) if $full10 >= $wb_full;
        return ('pressure', \@reasons, $sample);
    }

    push @reasons, 'below pressure thresholds';
    return ('normal', \@reasons, $sample);
}

1;
