package Zram::Pressure;

use strict;
use warnings;

use Exporter qw(import);
use Zram::Config qw(cfg);
use Zram::Logger qw(log_msg);
use Zram::Procfs qw(memory_pressure_snapshot);

our @EXPORT_OK = qw(determine_pressure_state memory_pressure_gate_met);

sub _mem_available_percent {
    my $snapshot = memory_pressure_snapshot();
    my $available = $snapshot->{mem_available_bytes};
    my $total = $snapshot->{mem_total_bytes};
    my $available_pct = $total > 0 ? int(($available * 100 + $total - 1) / $total) : 0;
    return (
        $available,
        $total,
        $available_pct,
        $snapshot->{psi_some_avg10_millionths},
        $snapshot->{psi_full_avg10_millionths},
    );
}

sub determine_pressure_state {
    return ('normal', ['pressure policy disabled'], {}) if !cfg('ZRAM_PRESSURE_ENABLED');

    my ($available, $total, $available_pct, $some_avg10, $full_avg10) = _mem_available_percent();
    my $minimum_free = cfg('ZRAM_MIN_FREE_MEMORY_BYTES');
    my @reasons;

    log_msg(
        'debug',
        'memory pressure gates ' .
        "some_avg10_millionths=$some_avg10 full_avg10_millionths=$full_avg10 " .
        "mem_available_bytes=$available mem_total_bytes=$total mem_available_pct=$available_pct " .
        "min_free_memory_bytes=$minimum_free"
    );

    if (($total > 0 && $available_pct <= cfg('ZRAM_EMERGENCY_MEM_AVAILABLE_PCT'))
        || $some_avg10 >= cfg('ZRAM_EMERGENCY_SOME_AVG10_THRESHOLD_UNITS')
        || $full_avg10 >= cfg('ZRAM_EMERGENCY_FULL_AVG10_THRESHOLD_UNITS')) {
        push @reasons, "MemAvailablePct=$available_pct<=" . cfg('ZRAM_EMERGENCY_MEM_AVAILABLE_PCT')
            if $total > 0 && $available_pct <= cfg('ZRAM_EMERGENCY_MEM_AVAILABLE_PCT');
        push @reasons, 'PSI some avg10 reached emergency threshold'
            if $some_avg10 >= cfg('ZRAM_EMERGENCY_SOME_AVG10_THRESHOLD_UNITS');
        push @reasons, 'PSI full avg10 reached emergency threshold'
            if $full_avg10 >= cfg('ZRAM_EMERGENCY_FULL_AVG10_THRESHOLD_UNITS');
        return ('emergency', \@reasons, {
            mem_available_bytes => $available,
            mem_total_bytes => $total,
            mem_available_percent => $available_pct,
            psi_some_avg10_millionths => $some_avg10,
            psi_full_avg10_millionths => $full_avg10,
        });
    }

    if (($total > 0 && $available_pct <= cfg('ZRAM_PRESSURE_MEM_AVAILABLE_PCT'))
        || $some_avg10 >= cfg('ZRAM_PRESSURE_SOME_AVG10_THRESHOLD_UNITS')
        || $full_avg10 >= cfg('ZRAM_PRESSURE_FULL_AVG10_THRESHOLD_UNITS')
        || ($minimum_free > 0 && $available > 0 && $available <= $minimum_free)) {
        push @reasons, "MemAvailablePct=$available_pct<=" . cfg('ZRAM_PRESSURE_MEM_AVAILABLE_PCT')
            if $total > 0 && $available_pct <= cfg('ZRAM_PRESSURE_MEM_AVAILABLE_PCT');
        push @reasons, 'PSI some avg10 reached pressure threshold'
            if $some_avg10 >= cfg('ZRAM_PRESSURE_SOME_AVG10_THRESHOLD_UNITS');
        push @reasons, 'PSI full avg10 reached pressure threshold'
            if $full_avg10 >= cfg('ZRAM_PRESSURE_FULL_AVG10_THRESHOLD_UNITS');
        push @reasons, 'MemAvailable bytes below configured floor'
            if $minimum_free > 0 && $available > 0 && $available <= $minimum_free;
        return ('pressure', \@reasons, {
            mem_available_bytes => $available,
            mem_total_bytes => $total,
            mem_available_percent => $available_pct,
            psi_some_avg10_millionths => $some_avg10,
            psi_full_avg10_millionths => $full_avg10,
        });
    }

    return ('normal', ['below pressure thresholds'], {
        mem_available_bytes => $available,
        mem_total_bytes => $total,
        mem_available_percent => $available_pct,
        psi_some_avg10_millionths => $some_avg10,
        psi_full_avg10_millionths => $full_avg10,
    });
}

sub memory_pressure_gate_met {
    my ($state) = determine_pressure_state();
    return $state eq 'normal' ? 0 : 1;
}

1;
