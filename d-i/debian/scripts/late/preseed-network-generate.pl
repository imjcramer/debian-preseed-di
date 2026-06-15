#!/usr/bin/perl
use strict;
use warnings;

use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use Socket qw(AF_INET AF_INET6 inet_ntop inet_pton);

my $MANAGED_MARKER = 'Managed by debian-preseed-di';
my %CFG = (
    PRESEED_NETWORK_TARGET_ROOT         => '/target',
    PRESEED_NETWORK_SYS_CLASS_NET       => '/sys/class/net',
    PRESEED_NETWORK_STATE_ENV           => '',
    PRESEED_NETWORK_WAIT_SECONDS        => '8',
    PRESEED_NETWORK_MODE                => 'static',
    PRESEED_NETWORK_LINK_TYPES          => 'ethernet',
    PRESEED_NETWORK_INSTALLER_MAC       => '',
    PRESEED_NETWORK_ETHERNET_MAC        => '',
    PRESEED_NETWORK_ETHERNET_IFACE      => 'preeth0',
    PRESEED_NETWORK_WIFI_MAC            => '',
    PRESEED_NETWORK_WIFI_IFACE          => 'prewifi0',
    PRESEED_NETWORK_HOSTNAME            => 'preseed-host',
    PRESEED_NETWORK_DOMAIN              => '',
    PRESEED_NETWORK_CLASSES_RAW         => '',
    PRESEED_NETWORK_SELECTED_CLASS_REFS => '',
    PRESEED_NETWORK_HOST_VARIANT        => '',
    PRESEED_NETWORK_IPV4_STATIC_RANGE   => '',
    PRESEED_NETWORK_IPV4_CIDR           => '',
    PRESEED_NETWORK_IPV4_GATEWAY        => '',
    PRESEED_NETWORK_IPV4_DNS            => '',
    PRESEED_NETWORK_IPV6_STATIC_RANGE   => '',
    PRESEED_NETWORK_IPV6_PREFIXLEN      => '',
    PRESEED_NETWORK_IPV6_GATEWAY        => '',
    PRESEED_NETWORK_IPV6_DNS            => '',
    PRESEED_NETWORK_WIFI_ESSID          => '',
    PRESEED_NETWORK_WIFI_ESSID_AGAIN    => '',
    PRESEED_NETWORK_WIFI_WPA            => '',
    PRESEED_NETWORK_WIFI_WEP            => '',
    PRESEED_NETWORK_WIFI_PSK_SECURITY   => 'wpa',
    SYSTEMD_LOG_LEVEL                   => $ENV{SYSTEMD_LOG_LEVEL} // 'error',
);
my %SUPPORTED_KEY = map { $_ => 1 } keys %CFG;
my %WARNED;
my %LOG_LEVEL_VALUE = (
    debug   => 10,
    info    => 20,
    warning => 30,
    error   => 40,
    none    => 99,
);

sub canonical_log_level {
    my ($level) = @_;
    $level = lc($level // 'info');
    return 'warning' if $level eq 'warn';
    return $level if exists $LOG_LEVEL_VALUE{$level};
    return 'info';
}

sub log_enabled {
    my ($level) = @_;
    my $requested = canonical_log_level($level);
    return 1 if $requested eq 'error';
    my $active = canonical_log_level($CFG{SYSTEMD_LOG_LEVEL});
    return 0 if $active eq 'none';
    return $LOG_LEVEL_VALUE{$requested} >= $LOG_LEVEL_VALUE{$active};
}

sub log_msg {
    my ($level, $message) = @_;
    $level = canonical_log_level($level);
    return if !log_enabled($level);
    print STDERR "$level: $message\n";
}

sub fatal {
    my ($message) = @_;
    log_msg('error', $message);
    exit 1;
}

sub warn_once {
    my ($key, $message) = @_;
    return if $WARNED{$key}++;
    log_msg('warning', $message);
}

sub usage {
    print STDERR "usage: " . basename($0) . " --input PATH [--state-env PATH]\n";
    exit 1;
}

sub parse_args {
    my $input = '';
    while (@ARGV) {
        my $arg = shift @ARGV;
        if ($arg eq '--input') {
            @ARGV || usage();
            $input = shift @ARGV;
            next;
        }
        if ($arg eq '--state-env') {
            @ARGV || usage();
            $CFG{PRESEED_NETWORK_STATE_ENV} = shift @ARGV;
            next;
        }
        usage();
    }
    usage() if $input eq '';
    return $input;
}

sub parse_shell_value {
    my ($raw) = @_;
    $raw =~ s/^\s+|\s+\z//g;
    return '' if $raw eq '';

    if (substr($raw, 0, 1) ne "'") {
        $raw =~ s/\s+#.*\z//;
        $raw =~ s/^\s+|\s+\z//g;
        return $raw;
    }

    my $out = '';
    my $i = 0;
    my $len = length($raw);
    while ($i < $len) {
        my $ch = substr($raw, $i, 1);
        if ($ch eq "'") {
            $i++;
            my $end = index($raw, "'", $i);
            die "unterminated single-quoted value" if $end < 0;
            $out .= substr($raw, $i, $end - $i);
            $i = $end + 1;
            next;
        }
        if (substr($raw, $i, 2) eq "\\'") {
            $out .= "'";
            $i += 2;
            next;
        }
        if ($ch =~ /\s/) {
            my $tail = substr($raw, $i);
            $tail =~ s/^\s+//;
            return $out if $tail eq '' || $tail =~ /\A#/;
        }
        die "unsupported shell value syntax near: " . substr($raw, $i, 16);
    }
    return $out;
}

sub read_input_env {
    my ($path) = @_;
    open my $fh, '<', $path or fatal("cannot read input env $path: $!");
    local $/;
    my $raw = <$fh>;
    close $fh or fatal("cannot close input env $path: $!");
    fatal("input env is too large: $path") if length($raw // '') > 65536;

    my @statements;
    my $current = '';
    for my $line (split /\n/, $raw, -1) {
        if ($current eq '' && $line =~ /\A\s*(?:#|\z)/) {
            next;
        }
        $current = length($current) ? "$current\n$line" : $line;
        my ($raw_value) = $current =~ /\A[A-Z_][A-Z0-9_]*=(.*)\z/s;
        fatal("invalid assignment in $path") if !defined $raw_value;
        my $complete = eval { parse_shell_value($raw_value); 1 };
        if (!$complete) {
            next if $@ =~ /unterminated single-quoted value/;
            fatal("invalid shell value in $path: $@");
        }
        push @statements, $current if $current =~ /\S/;
        $current = '';
    }
    fatal("unterminated quoted assignment in $path") if length($current);

    for my $stmt (@statements) {
        $stmt =~ s/^\s+|\s+\z//g;
        next if $stmt eq '' || $stmt =~ /\A#/;
        my ($key, $raw_value) = $stmt =~ /\A([A-Z_][A-Z0-9_]*)=(.*)\z/s
            or fatal("invalid assignment in $path");
        fatal("unsupported preseed network key: $key") if !$SUPPORTED_KEY{$key};
        my $value = eval { parse_shell_value($raw_value) };
        fatal("invalid shell value for $key: $@") if $@;
        fatal("control character in $key")
            if $value =~ /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/;
        $CFG{$key} = $value;
    }
}

sub shell_quote {
    my ($value) = @_;
    $value //= '';
    $value =~ s/'/'\\''/g;
    return "'$value'";
}

sub shell_assignment {
    my ($key, $value) = @_;
    fatal("invalid shell key: $key") if $key !~ /\A[A-Z_][A-Z0-9_]*\z/;
    return "$key=" . shell_quote($value) . "\n";
}

sub write_file_atomic {
    my ($path, $mode, $content) = @_;
    my $dir = dirname($path);
    make_path($dir, { mode => 0755 });
    my ($fh, $tmp) = tempfile('.' . basename($path) . '.tmp.XXXXXX', DIR => $dir, UNLINK => 0);
    eval {
        print {$fh} $content or die "write failed: $!";
        close $fh or die "close failed: $!";
        chmod $mode, $tmp or die "chmod failed: $!";
        rename $tmp, $path or die "rename failed: $!";
    };
    if ($@) {
        unlink $tmp if defined($tmp) && -e $tmp;
        fatal("failed to write $path atomically: $@");
    }
}

sub target_path {
    my ($path) = @_;
    my $root = $CFG{PRESEED_NETWORK_TARGET_ROOT};
    $root =~ s{/+\z}{};
    $root = '/' if $root eq '';
    return $path if $root eq '/';
    return "$root$path";
}

sub valid_token {
    my ($value) = @_;
    return defined($value) && $value ne '' && $value !~ /\s/ && $value =~ /\A[[:print:]]+\z/;
}

sub valid_iface_name {
    my ($name) = @_;
    return 0 if !defined($name) || $name eq '' || $name eq '.' || $name eq '..' || $name eq 'lo';
    return 0 if length($name) > 15;
    return $name =~ /\A[A-Za-z0-9_.-]+\z/ ? 1 : 0;
}

sub normalize_mac {
    my ($mac) = @_;
    $mac = lc($mac // '');
    $mac =~ s/^\s+|\s+\z//g;
    return $mac;
}

sub valid_mac {
    my ($mac) = @_;
    $mac = normalize_mac($mac);
    return 0 if $mac eq '00:00:00:00:00:00';
    return $mac =~ /\A[0-9a-f]{2}(?::[0-9a-f]{2}){5}\z/ ? 1 : 0;
}

sub validate_domain {
    my ($value) = @_;
    return if $value eq '';
    fatal('PRESEED_NETWORK_DOMAIN must be a valid DNS search domain')
        if length($value) > 253 || $value =~ /\A[.]|[.]\z|[.]{2}/;
    for my $part (split /\./, $value) {
        fatal('PRESEED_NETWORK_DOMAIN must be a valid DNS search domain')
            if $part eq '' || length($part) > 63 || $part !~ /\A[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\z/;
    }
}

sub link_types {
    my @out;
    my %seen;
    for my $item (split /[;,\s]+/, lc($CFG{PRESEED_NETWORK_LINK_TYPES} // '')) {
        next if $item eq '';
        fatal("unsupported link type: $item") if $item ne 'ethernet' && $item ne 'wifi';
        next if $seen{$item}++;
        push @out, $item;
    }
    fatal('PRESEED_NETWORK_LINK_TYPES must include ethernet and/or wifi') if !@out;
    return @out;
}

sub parse_ipv4 {
    my ($label, $value) = @_;
    fatal("$label must be an IPv4 dotted-quad address")
        if !defined($value) || $value !~ /\A[0-9]{1,3}(?:\.[0-9]{1,3}){3}\z/;
    my @octets = split /\./, $value;
    my $int = 0;
    for my $octet (@octets) {
        fatal("$label contains an invalid IPv4 octet")
            if $octet eq '' || $octet !~ /\A[0-9]+\z/ || length($octet) > 3 || $octet > 255;
        $int = ($int << 8) + $octet;
    }
    return $int;
}

sub format_ipv4 {
    my ($int) = @_;
    return join '.', map { ($int >> (8 * $_)) & 255 } reverse 0 .. 3;
}

sub parse_prefix {
    my ($label, $value, $max) = @_;
    fatal("$label must be an integer between 1 and $max")
        if !defined($value) || $value !~ /\A[0-9]+\z/ || $value < 1 || $value > $max;
    return int($value);
}

sub ipv4_netmask {
    my ($prefix) = @_;
    my $mask = $prefix == 0 ? 0 : ((0xffffffff << (32 - $prefix)) & 0xffffffff);
    return format_ipv4($mask);
}

sub ipv4_network_cidr {
    my ($address, $prefix) = @_;
    my $mask = $prefix == 0 ? 0 : ((0xffffffff << (32 - $prefix)) & 0xffffffff);
    return format_ipv4($address & $mask) . "/$prefix";
}

sub ipv4_host_is_network_or_broadcast {
    my ($address, $prefix) = @_;
    return 0 if $prefix >= 31;
    my $mask = ((0xffffffff << (32 - $prefix)) & 0xffffffff);
    my $network = $address & $mask;
    my $broadcast = $network | ((~$mask) & 0xffffffff);
    return $address == $network || $address == $broadcast;
}

sub parse_ipv4_range {
    my ($raw) = @_;
    my ($ip, $prefix) = $raw =~ /\A([^\/]+)\/([0-9]{1,2})\z/
        or fatal('PRESEED_NETWORK_IPV4_STATIC_RANGE must be IPv4/CIDR host-start pool');
    my $addr = parse_ipv4('PRESEED_NETWORK_IPV4_STATIC_RANGE', $ip);
    $prefix = parse_prefix('PRESEED_NETWORK_IPV4_STATIC_RANGE prefix', $prefix, 32);
    my $count = 2 ** (32 - $prefix);
    fatal('PRESEED_NETWORK_IPV4_STATIC_RANGE must contain no more than 4096 addresses')
        if $count > 4096;
    fatal('PRESEED_NETWORK_IPV4_STATIC_RANGE exceeds the IPv4 address space')
        if $addr + $count - 1 > 0xffffffff;
    return ($addr, $count);
}

sub normalize_address_list {
    my ($value) = @_;
    $value //= '';
    $value =~ s/[, \t\r\n]+/ /g;
    $value =~ s/\A\s+|\s+\z//g;
    return $value;
}

sub validate_ipv4_dns {
    my ($raw) = @_;
    my $dns = normalize_address_list($raw);
    fatal('PRESEED_NETWORK_IPV4_DNS must contain at least one IPv4 address') if $dns eq '';
    my @items = split / /, $dns;
    fatal('PRESEED_NETWORK_IPV4_DNS must contain no more than five addresses') if @items > 5;
    parse_ipv4('PRESEED_NETWORK_IPV4_DNS entry', $_) for @items;
    return $dns;
}

sub validate_ipv6_dns {
    my ($raw) = @_;
    my $dns = normalize_address_list($raw);
    fatal('PRESEED_NETWORK_IPV6_DNS must contain at least one IPv6 address') if $dns eq '';
    my @items = split / /, $dns;
    fatal('PRESEED_NETWORK_IPV6_DNS must contain no more than five addresses') if @items > 5;
    for my $item (@items) {
        fatal('PRESEED_NETWORK_IPV6_DNS entries must be IPv6')
            if !defined inet_pton(AF_INET6, $item);
    }
    return $dns;
}

sub ipv6_to_bytes {
    my ($label, $value) = @_;
    my $packed = inet_pton(AF_INET6, $value);
    fatal("$label must be an IPv6 address") if !defined $packed;
    return [unpack 'C16', $packed];
}

sub bytes_to_ipv6 {
    my ($bytes) = @_;
    return inet_ntop(AF_INET6, pack('C16', @{$bytes}));
}

sub mask_ipv6 {
    my ($bytes, $prefix) = @_;
    my @out = @{$bytes};
    for my $i (0 .. 15) {
        my $remain = $prefix - ($i * 8);
        if ($remain >= 8) {
            next;
        }
        if ($remain <= 0) {
            $out[$i] = 0;
            next;
        }
        my $mask = (0xff << (8 - $remain)) & 0xff;
        $out[$i] &= $mask;
    }
    return \@out;
}

sub add_ipv6_offset {
    my ($bytes, $offset) = @_;
    my @out = @{$bytes};
    for (my $i = 15; $i >= 0 && $offset > 0; $i--) {
        my $sum = $out[$i] + ($offset & 0xff);
        $out[$i] = $sum & 0xff;
        $offset = ($offset >> 8) + ($sum >> 8);
    }
    fatal('IPv6 address generation overflowed range') if $offset > 0;
    return \@out;
}

sub same_ipv6 {
    my ($left, $right) = @_;
    for my $i (0 .. 15) {
        return 0 if $left->[$i] != $right->[$i];
    }
    return 1;
}

sub parse_ipv6_range {
    my ($raw) = @_;
    my ($addr, $prefix) = $raw =~ /\A([^\/]+)\/([0-9]{1,3})\z/
        or fatal('PRESEED_NETWORK_IPV6_STATIC_RANGE must be IPv6/CIDR host-start pool');
    $prefix = parse_prefix('PRESEED_NETWORK_IPV6_STATIC_RANGE prefix', $prefix, 128);
    my $host_bits = 128 - $prefix;
    fatal('PRESEED_NETWORK_IPV6_STATIC_RANGE must contain no more than 1024 addresses')
        if $host_bits > 10;
    my $base = ipv6_to_bytes('PRESEED_NETWORK_IPV6_STATIC_RANGE', $addr);
    return ($base, 2 ** $host_bits);
}

sub command_exists {
    my ($command) = @_;
    for my $dir (split /:/, $ENV{PATH} || '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin') {
        return 1 if -x "$dir/$command";
    }
    return 0;
}

sub run_quiet {
    my (@cmd) = @_;
    my $pid = fork();
    fatal("fork failed for $cmd[0]: $!") if !defined $pid;
    if ($pid == 0) {
        open STDOUT, '>', '/dev/null';
        open STDERR, '>', '/dev/null';
        exec @cmd;
        exit 127;
    }
    waitpid $pid, 0;
    return $? == 0 ? 1 : 0;
}

sub capture_quiet {
    my (@cmd) = @_;
    open my $fh, '-|', @cmd or return '';
    local $/;
    my $out = <$fh>;
    close $fh;
    return $out // '';
}

sub ipv4_in_use {
    my ($iface, $candidate) = @_;
    my $probed = 0;
    if (command_exists('ip')) {
        my $addr_out = capture_quiet('ip', '-o', '-4', 'addr', 'show');
        return 1 if $addr_out =~ m{\binet\s+\Q$candidate\E/};
    }
    if ($iface ne '' && command_exists('arping')) {
        $probed = 1;
        return 1 if run_quiet('arping', '-c', '1', '-w', '2', '-I', $iface, $candidate);
    }
    if (command_exists('ping')) {
        $probed = 1;
        return 1 if run_quiet('ping', '-4', '-c', '1', '-W', '1', $candidate);
    }
    if (command_exists('ip')) {
        my $out = capture_quiet('ip', '-4', 'neigh', 'show', 'to', $candidate);
        return 1 if $out =~ /\S/ && $out !~ /\b(?:FAILED|INCOMPLETE)\b/;
    }
    warn_once('ipv4_probe', 'no IPv4 active probe command was available; relying on neighbor table only')
        if !$probed;
    return 0;
}

sub ipv6_in_use {
    my ($candidate) = @_;
    my $probed = 0;
    if (command_exists('ip')) {
        my $addr_out = capture_quiet('ip', '-o', '-6', 'addr', 'show');
        return 1 if $addr_out =~ m{\binet6\s+\Q$candidate\E/};
    }
    if (command_exists('ping')) {
        $probed = 1;
        return 1 if run_quiet('ping', '-6', '-c', '1', '-W', '1', $candidate);
    } elsif (command_exists('ping6')) {
        $probed = 1;
        return 1 if run_quiet('ping6', '-c', '1', '-W', '1', $candidate);
    }
    if (command_exists('ip')) {
        my $out = capture_quiet('ip', '-6', 'neigh', 'show', 'to', $candidate);
        return 1 if $out =~ /\S/ && $out !~ /\b(?:FAILED|INCOMPLETE)\b/;
    }
    warn_once('ipv6_probe', 'no IPv6 active probe command was available; relying on neighbor table only')
        if !$probed;
    return 0;
}

sub fnv1a32 {
    my ($text) = @_;
    my $hash = 2166136261;
    for my $byte (unpack 'C*', $text) {
        $hash ^= $byte;
        $hash = ($hash * 16777619) & 0xffffffff;
    }
    return $hash;
}

sub read_sys_value {
    my ($path) = @_;
    open my $fh, '<', $path or return undef;
    my $value = <$fh>;
    close $fh;
    return undef if !defined $value;
    chomp $value;
    return $value;
}

sub iface_is_wifi {
    my ($sys_iface) = @_;
    return -d "$sys_iface/wireless" || -d "$sys_iface/phy80211";
}

sub iface_matches_type {
    my ($iface, $sys_iface, $link_type) = @_;
    return 0 if !valid_iface_name($iface);
    return 0 if !-e "$sys_iface/device";
    my $type = read_sys_value("$sys_iface/type") // '';
    return 0 if $type ne '1';
    return iface_is_wifi($sys_iface) ? 1 : 0 if $link_type eq 'wifi';
    return iface_is_wifi($sys_iface) ? 0 : 1;
}

sub target_mac_for_link {
    my ($link_type) = @_;
    return $CFG{PRESEED_NETWORK_WIFI_MAC}
        if $link_type eq 'wifi' && $CFG{PRESEED_NETWORK_WIFI_MAC} ne '';
    return $CFG{PRESEED_NETWORK_ETHERNET_MAC}
        if $link_type eq 'ethernet' && $CFG{PRESEED_NETWORK_ETHERNET_MAC} ne '';
    return $CFG{PRESEED_NETWORK_INSTALLER_MAC};
}

sub iface_score {
    my ($iface, $sys_iface, $link_type) = @_;
    my $mac = normalize_mac(read_sys_value("$sys_iface/address") // '');
    my $carrier = read_sys_value("$sys_iface/carrier") // '0';
    my $operstate = read_sys_value("$sys_iface/operstate") // '';
    my $target_mac = target_mac_for_link($link_type);
    my $mac_score = ($target_mac ne '' && $mac eq $target_mac) ? 0 : 10;
    my $link_score = $carrier eq '1' ? 0 : ($operstate eq 'up' ? 10 : 20);
    return sprintf('%02d%02d-%s', $mac_score, $link_score, $iface);
}

sub candidates_for_link {
    my ($link_type) = @_;
    my $sys_class = $CFG{PRESEED_NETWORK_SYS_CLASS_NET};
    opendir my $dh, $sys_class or fatal("cannot read $sys_class: $!");
    my @entries = grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh;

    my @candidates;
    for my $iface (sort @entries) {
        my $sys_iface = "$sys_class/$iface";
        next if !iface_matches_type($iface, $sys_iface, $link_type);
        my $mac = normalize_mac(read_sys_value("$sys_iface/address") // '');
        push @candidates, {
            iface => $iface,
            mac   => $mac,
            score => iface_score($iface, $sys_iface, $link_type),
        };
    }
    return sort { $a->{score} cmp $b->{score} } @candidates;
}

sub select_iface {
    my ($link_type) = @_;
    my @candidates = candidates_for_link($link_type);
    fatal("no $link_type adapter detected for static network configuration") if !@candidates;
    return $candidates[0];
}

sub select_ipv4 {
    my ($link_type, $iface, $mac, $allocated) = @_;
    my ($range_base, $range_count) = parse_ipv4_range($CFG{PRESEED_NETWORK_IPV4_STATIC_RANGE});
    my $prefix = parse_prefix('PRESEED_NETWORK_IPV4_CIDR', $CFG{PRESEED_NETWORK_IPV4_CIDR}, 32);
    my $gateway = parse_ipv4('PRESEED_NETWORK_IPV4_GATEWAY', $CFG{PRESEED_NETWORK_IPV4_GATEWAY});
    my $start = fnv1a32(join('|', $CFG{PRESEED_NETWORK_HOSTNAME}, $link_type, $mac, $CFG{PRESEED_NETWORK_IPV4_STATIC_RANGE})) % $range_count;

    for my $step (0 .. ($range_count - 1)) {
        my $candidate_int = ($range_base + (($start + $step) % $range_count)) & 0xffffffff;
        my $candidate = format_ipv4($candidate_int);
        next if $candidate_int == $gateway;
        next if ipv4_host_is_network_or_broadcast($candidate_int, $prefix);
        next if $allocated->{$candidate}++;
        if (ipv4_in_use($iface, $candidate)) {
            log_msg('info', "IPv4 candidate $candidate appears to be in use; trying next address");
            next;
        }
        return ($candidate, "$candidate/$prefix", "$candidate/32", ipv4_network_cidr($candidate_int, $prefix));
    }
    fatal("no available IPv4 address found in $CFG{PRESEED_NETWORK_IPV4_STATIC_RANGE}");
}

sub select_ipv6 {
    my ($link_type, $mac, $allocated) = @_;
    my ($range_base, $range_count) = parse_ipv6_range($CFG{PRESEED_NETWORK_IPV6_STATIC_RANGE});
    my $prefix = parse_prefix('PRESEED_NETWORK_IPV6_PREFIXLEN', $CFG{PRESEED_NETWORK_IPV6_PREFIXLEN}, 128);
    my $gateway = ipv6_to_bytes('PRESEED_NETWORK_IPV6_GATEWAY', $CFG{PRESEED_NETWORK_IPV6_GATEWAY});
    my $start = fnv1a32(join('|', $CFG{PRESEED_NETWORK_HOSTNAME}, $link_type, $mac, $CFG{PRESEED_NETWORK_IPV6_STATIC_RANGE})) % $range_count;

    for my $step (0 .. ($range_count - 1)) {
        my $candidate_bytes = add_ipv6_offset($range_base, ($start + $step) % $range_count);
        next if same_ipv6($candidate_bytes, $gateway);
        my $candidate = bytes_to_ipv6($candidate_bytes);
        next if $allocated->{$candidate}++;
        if (ipv6_in_use($candidate)) {
            log_msg('info', "IPv6 candidate $candidate appears to be in use; trying next address");
            next;
        }
        my $network = bytes_to_ipv6(mask_ipv6($candidate_bytes, $prefix)) . "/$prefix";
        return ($candidate, "$candidate/$prefix", "$candidate/128", $network);
    }
    fatal("no available IPv6 address found in $CFG{PRESEED_NETWORK_IPV6_STATIC_RANGE}");
}

sub validate_wifi {
    my @types = @_;
    my $has_wifi = grep { $_ eq 'wifi' } @types;
    return if !$has_wifi;
    fatal('PRESEED_NETWORK_WIFI_ESSID is required for Wi-Fi static configuration')
        if !valid_token($CFG{PRESEED_NETWORK_WIFI_ESSID}) || length($CFG{PRESEED_NETWORK_WIFI_ESSID}) > 32;
    if ($CFG{PRESEED_NETWORK_WIFI_ESSID_AGAIN} ne ''
        && $CFG{PRESEED_NETWORK_WIFI_ESSID_AGAIN} ne $CFG{PRESEED_NETWORK_WIFI_ESSID}) {
        fatal('PRESEED_NETWORK_WIFI_ESSID_AGAIN must match PRESEED_NETWORK_WIFI_ESSID');
    }
    my $security = lc($CFG{PRESEED_NETWORK_WIFI_PSK_SECURITY});
    fatal('PRESEED_NETWORK_WIFI_PSK_SECURITY must be open, wep, open/wep, wpa, or sae')
        if $security ne 'open' && $security ne 'wep' && $security ne 'open/wep'
        && $security ne 'wpa' && $security ne 'sae';
    if ($security eq 'wpa' || $security eq 'sae') {
        my $psk = $CFG{PRESEED_NETWORK_WIFI_WPA};
        fatal('PRESEED_NETWORK_WIFI_WPA is required for WPA/SAE Wi-Fi')
            if !valid_token($psk);
        my $length = length($psk);
        return if $length >= 8 && $length <= 63;
        fatal('PRESEED_NETWORK_WIFI_WPA must be 8-63 printable characters or 64 hex characters')
            if $psk !~ /\A[0-9A-Fa-f]{64}\z/;
    }
    if ($security eq 'wep' && !valid_token($CFG{PRESEED_NETWORK_WIFI_WEP})) {
        fatal('PRESEED_NETWORK_WIFI_WEP is required when WIFI_PSK_SECURITY=wep');
    }
}

sub validate_config {
    fatal('SYSTEMD_LOG_LEVEL must be debug, info, warning, error, or none')
        if lc($CFG{SYSTEMD_LOG_LEVEL}) !~ /\A(?:debug|info|warn|warning|error|none)\z/;
    $CFG{SYSTEMD_LOG_LEVEL} = canonical_log_level($CFG{SYSTEMD_LOG_LEVEL});
    fatal('PRESEED_NETWORK_TARGET_ROOT must be absolute')
        if $CFG{PRESEED_NETWORK_TARGET_ROOT} !~ m{\A/};
    fatal('target root is missing: ' . $CFG{PRESEED_NETWORK_TARGET_ROOT})
        if !-d $CFG{PRESEED_NETWORK_TARGET_ROOT};
    fatal('PRESEED_NETWORK_SYS_CLASS_NET must be absolute')
        if $CFG{PRESEED_NETWORK_SYS_CLASS_NET} !~ m{\A/};
    fatal('sysfs net directory is missing: ' . $CFG{PRESEED_NETWORK_SYS_CLASS_NET})
        if !-d $CFG{PRESEED_NETWORK_SYS_CLASS_NET};
    fatal('PRESEED_NETWORK_MODE must be static')
        if $CFG{PRESEED_NETWORK_MODE} ne 'static';
    parse_prefix('PRESEED_NETWORK_WAIT_SECONDS', $CFG{PRESEED_NETWORK_WAIT_SECONDS}, 60);
    validate_domain($CFG{PRESEED_NETWORK_DOMAIN});
    for my $key (qw(PRESEED_NETWORK_INSTALLER_MAC PRESEED_NETWORK_ETHERNET_MAC PRESEED_NETWORK_WIFI_MAC)) {
        next if $CFG{$key} eq '';
        fatal("$key is not a valid MAC address") if !valid_mac($CFG{$key});
        $CFG{$key} = normalize_mac($CFG{$key});
    }
    fatal('PRESEED_NETWORK_ETHERNET_IFACE is not a valid interface name')
        if !valid_iface_name($CFG{PRESEED_NETWORK_ETHERNET_IFACE});
    fatal('PRESEED_NETWORK_WIFI_IFACE is not a valid interface name')
        if !valid_iface_name($CFG{PRESEED_NETWORK_WIFI_IFACE});
    fatal('PRESEED_NETWORK_ETHERNET_IFACE and PRESEED_NETWORK_WIFI_IFACE must differ')
        if $CFG{PRESEED_NETWORK_ETHERNET_IFACE} eq $CFG{PRESEED_NETWORK_WIFI_IFACE};
    parse_ipv4_range($CFG{PRESEED_NETWORK_IPV4_STATIC_RANGE});
    parse_prefix('PRESEED_NETWORK_IPV4_CIDR', $CFG{PRESEED_NETWORK_IPV4_CIDR}, 32);
    parse_ipv4('PRESEED_NETWORK_IPV4_GATEWAY', $CFG{PRESEED_NETWORK_IPV4_GATEWAY});
    $CFG{PRESEED_NETWORK_IPV4_DNS} = validate_ipv4_dns($CFG{PRESEED_NETWORK_IPV4_DNS});
    parse_ipv6_range($CFG{PRESEED_NETWORK_IPV6_STATIC_RANGE});
    parse_prefix('PRESEED_NETWORK_IPV6_PREFIXLEN', $CFG{PRESEED_NETWORK_IPV6_PREFIXLEN}, 128);
    ipv6_to_bytes('PRESEED_NETWORK_IPV6_GATEWAY', $CFG{PRESEED_NETWORK_IPV6_GATEWAY});
    $CFG{PRESEED_NETWORK_IPV6_DNS} = validate_ipv6_dns($CFG{PRESEED_NETWORK_IPV6_DNS});
    validate_wifi(link_types());
}

sub iface_performance_options {
    my ($metric) = @_;
    return (
        "    metric $metric",
        '    mtu 1500',
        '    pre-up /sbin/ip link set dev "$IFACE" txqueuelen 1000 2>/dev/null || true',
        '    post-up /sbin/ip link set dev "$IFACE" txqueuelen 1000 2>/dev/null || true',
        '    post-up /usr/sbin/ethtool -K "$IFACE" rx on tx on sg on tso on gso on gro on 2>/dev/null || true',
    );
}

sub wifi_options {
    my $security = lc($CFG{PRESEED_NETWORK_WIFI_PSK_SECURITY});
    $security = 'wep' if $security eq 'open/wep' && $CFG{PRESEED_NETWORK_WIFI_WEP} ne '';
    $security = 'open' if $security eq 'open/wep';

    my @lines = ("    wpa-ssid $CFG{PRESEED_NETWORK_WIFI_ESSID}");
    if ($security eq 'sae') {
        push @lines,
            '    wpa-key-mgmt SAE',
            '    wpa-proto RSN',
            '    wpa-pairwise CCMP',
            '    wpa-group CCMP',
            '    wpa-ieee80211w 2',
            "    wpa-psk $CFG{PRESEED_NETWORK_WIFI_WPA}";
    } elsif ($security eq 'wpa') {
        push @lines,
            '    wpa-key-mgmt WPA-PSK',
            '    wpa-proto RSN',
            '    wpa-pairwise CCMP',
            '    wpa-group CCMP',
            "    wpa-psk $CFG{PRESEED_NETWORK_WIFI_WPA}";
    } elsif ($security eq 'wep') {
        push @lines,
            '    wpa-key-mgmt NONE',
            "    wpa-wep-key0 $CFG{PRESEED_NETWORK_WIFI_WEP}",
            '    wpa-wep-tx-keyidx 0';
    } else {
        push @lines, '    wpa-key-mgmt NONE';
    }
    return @lines;
}

sub render_iface_stanza {
    my ($link_type, $record, $metric) = @_;
    my @lines = (
        "# $link_type adapter: $record->{iface} ($record->{mac}); detected during install as $record->{detected_iface}",
        "auto $record->{iface}",
        "allow-hotplug $record->{iface}",
        "iface $record->{iface} inet static",
        "    address $record->{ipv4_address}",
        "    netmask $record->{ipv4_netmask}",
        "    gateway $CFG{PRESEED_NETWORK_IPV4_GATEWAY}",
        "    dns-nameservers $CFG{PRESEED_NETWORK_IPV4_DNS}",
    );
    push @lines, "    dns-search $CFG{PRESEED_NETWORK_DOMAIN}"
        if $CFG{PRESEED_NETWORK_DOMAIN} ne '';
    push @lines, wifi_options() if $link_type eq 'wifi';
    push @lines, iface_performance_options($metric);
    push @lines,
        '',
        "iface $record->{iface} inet6 static",
        "    address $record->{ipv6_address}",
        "    netmask $CFG{PRESEED_NETWORK_IPV6_PREFIXLEN}",
        "    gateway $CFG{PRESEED_NETWORK_IPV6_GATEWAY}",
        "    dns-nameservers $CFG{PRESEED_NETWORK_IPV6_DNS}";
    push @lines, iface_performance_options($metric);
    return join("\n", @lines) . "\n";
}

sub boot_iface_name {
    my ($link_type) = @_;
    return $link_type eq 'wifi' ? $CFG{PRESEED_NETWORK_WIFI_IFACE} : $CFG{PRESEED_NETWORK_ETHERNET_IFACE};
}

sub render_link_file {
    my ($link_type, $record) = @_;
    return <<"EOF";
# $MANAGED_MARKER.
# Keep target ifupdown stanzas independent of d-i's temporary adapter names.

[Match]
MACAddress=$record->{mac}

[Link]
NamePolicy=
Name=$record->{iface}
EOF
}

sub render_networkmanager_unmanaged {
    my ($selected) = @_;
    my @matches;
    my %seen;

    for my $link_type (link_types()) {
        next if !exists $selected->{$link_type};
        my $match = "interface-name:$selected->{$link_type}->{iface}";
        push @matches, $match if !$seen{$match}++;
    }

    for my $link_type (link_types()) {
        next if !exists $selected->{$link_type};
        my $mac = normalize_mac($selected->{$link_type}->{mac});
        next if !valid_mac($mac);
        my $match = "mac:$mac";
        push @matches, $match if !$seen{$match}++;
    }

    return <<"EOF";
# $MANAGED_MARKER.
#
# The static preseed handoff owns these generated ifupdown adapters.
# Keep NetworkManager available for desktop clients, but prevent it from racing
# ifupdown by matching both the deterministic boot names and the detected MACs.

[keyfile]
unmanaged-devices=@{[ join(';', @matches) ]}
EOF
}

sub render_interfaces_base {
    return <<"EOF";
# $MANAGED_MARKER.
# Static network stanzas are generated during d-i late_command.

auto lo
iface lo inet loopback

source /etc/network/interfaces.d/*
EOF
}

sub write_runtime_defaults {
    my ($selected) = @_;
    my @lines = (
        "# $MANAGED_MARKER.\n",
        "# Generated during d-i late_command. Root-only because Wi-Fi metadata may be sensitive.\n",
        shell_assignment('PRESEED_NETWORK_MODE', 'static'),
        shell_assignment('PRESEED_NETWORK_LINK_TYPES', join(' ', link_types())),
        shell_assignment('PRESEED_NETWORK_HOSTNAME', $CFG{PRESEED_NETWORK_HOSTNAME}),
        shell_assignment('PRESEED_NETWORK_DOMAIN', $CFG{PRESEED_NETWORK_DOMAIN}),
        shell_assignment('PRESEED_NETWORK_CLASSES_RAW', $CFG{PRESEED_NETWORK_CLASSES_RAW}),
        shell_assignment('PRESEED_NETWORK_SELECTED_CLASS_REFS', $CFG{PRESEED_NETWORK_SELECTED_CLASS_REFS}),
        shell_assignment('PRESEED_NETWORK_HOST_VARIANT', $CFG{PRESEED_NETWORK_HOST_VARIANT}),
        shell_assignment('SYSTEMD_LOG_LEVEL', $CFG{SYSTEMD_LOG_LEVEL}),
        shell_assignment('PRESEED_NETWORK_IPV4_GATEWAY', $CFG{PRESEED_NETWORK_IPV4_GATEWAY}),
        shell_assignment('PRESEED_NETWORK_IPV4_DNS', $CFG{PRESEED_NETWORK_IPV4_DNS}),
        shell_assignment('PRESEED_NETWORK_IPV6_GATEWAY', $CFG{PRESEED_NETWORK_IPV6_GATEWAY}),
        shell_assignment('PRESEED_NETWORK_IPV6_DNS', $CFG{PRESEED_NETWORK_IPV6_DNS}),
        shell_assignment('PRESEED_NETWORK_WIFI_PSK_SECURITY', lc($CFG{PRESEED_NETWORK_WIFI_PSK_SECURITY})),
    );
    push @lines, shell_assignment('PRESEED_NETWORK_WIFI_ESSID', $CFG{PRESEED_NETWORK_WIFI_ESSID})
        if exists $selected->{wifi};
    for my $link_type (link_types()) {
        next if !exists $selected->{$link_type};
        my $upper = uc($link_type);
        my $r = $selected->{$link_type};
        push @lines,
            shell_assignment("PRESEED_NETWORK_${upper}_IFACE", $r->{iface}),
            shell_assignment("PRESEED_NETWORK_${upper}_MAC", $r->{mac}),
            shell_assignment("PRESEED_NETWORK_${upper}_IPV4_CIDR", $r->{ipv4_cidr}),
            shell_assignment("PRESEED_NETWORK_${upper}_IPV6_CIDR", $r->{ipv6_cidr});
    }
    push @lines,
        shell_assignment('PRESEED_NETWORK_IPV4_HOST_CIDRS', join(' ', map { $selected->{$_}->{ipv4_host_cidr} } grep { exists $selected->{$_} } link_types())),
        shell_assignment('PRESEED_NETWORK_IPV4_NETWORK_CIDRS', join(' ', map { $selected->{$_}->{ipv4_network_cidr} } grep { exists $selected->{$_} } link_types())),
        shell_assignment('PRESEED_NETWORK_IPV6_HOST_CIDRS', join(' ', map { $selected->{$_}->{ipv6_host_cidr} } grep { exists $selected->{$_} } link_types())),
        shell_assignment('PRESEED_NETWORK_IPV6_NETWORK_CIDRS', join(' ', map { $selected->{$_}->{ipv6_network_cidr} } grep { exists $selected->{$_} } link_types()));
    write_file_atomic(target_path('/etc/default/preseed-network'), 0600, join('', @lines));
}

sub write_state_env {
    my ($selected) = @_;
    return if $CFG{PRESEED_NETWORK_STATE_ENV} eq '';
    my @links = grep { exists $selected->{$_} } link_types();
    my @lines = (
        shell_assignment('PRESEED_NETWORK_GENERATED', 'true'),
        shell_assignment('PRESEED_NETWORK_IPV4_ENABLED', 'true'),
        shell_assignment('PRESEED_NETWORK_IPV6_ENABLED', 'true'),
        shell_assignment('PRESEED_NETWORK_IPV4_HOST_CIDRS', join(' ', map { $selected->{$_}->{ipv4_host_cidr} } @links)),
        shell_assignment('PRESEED_NETWORK_IPV4_NETWORK_CIDRS', join(' ', map { $selected->{$_}->{ipv4_network_cidr} } @links)),
        shell_assignment('PRESEED_NETWORK_IPV6_HOST_CIDRS', join(' ', map { $selected->{$_}->{ipv6_host_cidr} } @links)),
        shell_assignment('PRESEED_NETWORK_IPV6_NETWORK_CIDRS', join(' ', map { $selected->{$_}->{ipv6_network_cidr} } @links)),
        shell_assignment('PRESEED_NETWORK_IPV6_HOST_CIDR', $selected->{$links[0]}->{ipv6_host_cidr}),
        shell_assignment('PRESEED_NETWORK_IPV6_NETWORK_CIDR', $selected->{$links[0]}->{ipv6_network_cidr}),
        shell_assignment('PRESEED_NETWORK_IPV6_CIDR', $selected->{$links[0]}->{ipv6_cidr}),
    );
    write_file_atomic($CFG{PRESEED_NETWORK_STATE_ENV}, 0600, join('', @lines));
}

sub main {
    my $input = parse_args();
    read_input_env($input);
    validate_config();

    my %selected;
    my %allocated_v4;
    my %allocated_v6;
    my $netmask = ipv4_netmask($CFG{PRESEED_NETWORK_IPV4_CIDR});
    for my $link_type (link_types()) {
        my $candidate = select_iface($link_type);
        my ($ipv4, $ipv4_cidr, $ipv4_host, $ipv4_network) =
            select_ipv4($link_type, $candidate->{iface}, $candidate->{mac}, \%allocated_v4);
        my ($ipv6, $ipv6_cidr, $ipv6_host, $ipv6_network) =
            select_ipv6($link_type, $candidate->{mac}, \%allocated_v6);
        $selected{$link_type} = {
            iface             => boot_iface_name($link_type),
            detected_iface    => $candidate->{iface},
            mac               => $candidate->{mac},
            ipv4_address      => $ipv4,
            ipv4_netmask      => $netmask,
            ipv4_cidr         => $ipv4_cidr,
            ipv4_host_cidr    => $ipv4_host,
            ipv4_network_cidr => $ipv4_network,
            ipv6_address      => $ipv6,
            ipv6_cidr         => $ipv6_cidr,
            ipv6_host_cidr    => $ipv6_host,
            ipv6_network_cidr => $ipv6_network,
        };
    }

    my @parts = (
        "# $MANAGED_MARKER.",
        '# Generated during d-i late_command; preseed-network.service only validates it at boot.',
        '',
    );
    my $metric = 100;
    for my $link_type (link_types()) {
        push @parts, render_iface_stanza($link_type, $selected{$link_type}, $metric);
        $metric += 100;
    }

    make_path(
        target_path('/etc/network'),
        target_path('/etc/network/interfaces.d'),
        target_path('/etc/NetworkManager/conf.d'),
        { mode => 0755 },
    );
    write_file_atomic(target_path('/etc/network/interfaces'), 0644, render_interfaces_base());
    write_file_atomic(
        target_path('/etc/network/interfaces.d/50-preseed-network'),
        exists($selected{wifi}) ? 0600 : 0644,
        join("\n", @parts)
    );
    for my $link_type (link_types()) {
        my $link_path = $link_type eq 'wifi'
            ? '/etc/systemd/network/11-preseed-wifi.link'
            : '/etc/systemd/network/10-preseed-ethernet.link';
        write_file_atomic(target_path($link_path), 0644, render_link_file($link_type, $selected{$link_type}));
    }
    write_file_atomic(
        target_path('/etc/NetworkManager/conf.d/90-preseed-network-unmanaged.conf'),
        0644,
        render_networkmanager_unmanaged(\%selected),
    );
    write_runtime_defaults(\%selected);
    write_state_env(\%selected);

    my $summary = join ', ', map {
        "$_=$selected{$_}->{iface} ipv4=$selected{$_}->{ipv4_cidr} ipv6=$selected{$_}->{ipv6_cidr}"
    } link_types();
    log_msg('info', "generated static target network configuration: $summary");
}

main();
