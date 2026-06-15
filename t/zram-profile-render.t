use strict;
use warnings;

use File::Temp qw(tempfile);
use FindBin qw($Bin);
use lib "$Bin/../d-i/debian/hooks/shared/target/usr/local/libexec/zram-writeback";
use Test::More;
use Zram::Config qw(load_config validate_config);

my $root = "$Bin/..";
my $template = "$root/d-i/debian/hooks/shared/target/etc/zram-writeback.conf";
open my $tfh, '<', $template or die "open $template: $!";
my $template_text = do { local $/; <$tfh> };
close $tfh or die "close $template: $!";
my $default_template = "$root/d-i/debian/hooks/shared/target/etc/default/zram-writeback.tmpl";
open my $dfh, '<', $default_template or die "open $default_template: $!";
my $default_template_text = do { local $/; <$dfh> };
close $dfh or die "close $default_template: $!";
my $setup_helper = "$root/d-i/debian/hooks/shared/target/usr/local/sbin/zram-device-setup.tmpl";
open my $shfh, '<', $setup_helper or die "open $setup_helper: $!";
my $setup_helper_text = do { local $/; <$shfh> };
close $shfh or die "close $setup_helper: $!";
my @unit_templates = (
    "$root/d-i/debian/hooks/shared/target/etc/systemd/system/zram-setup.service.tmpl",
    "$root/d-i/debian/hooks/shared/target/etc/systemd/system/zram-writeback.service.tmpl",
    "$root/d-i/debian/hooks/shared/target/etc/systemd/system/zram-writebackd.service.tmpl",
    "$root/d-i/debian/hooks/shared/target/etc/systemd/system/zram-idle-writeback.timer.tmpl",
    "$root/d-i/debian/hooks/shared/target/etc/systemd/system/zram-cold-tier.timer.tmpl",
);

sub read_env_file {
    my ($path) = @_;
    open my $fh, '<', $path or die "open $path: $!";
    my %env;
    while (my $line = <$fh>) {
        next if $line =~ /\A\s*(?:#|\z)/;
        if ($line =~ /\A([A-Z0-9_]+)="([^"]*)"\s*(?:#.*)?\z/) {
            $env{$1} = $2;
        }
    }
    close $fh or die "close $path: $!";
    return %env;
}

my @profiles = sort glob "$root/d-i/debian/hosts/profiles/*/*.env";
ok(@profiles > 0, 'found concrete host profiles');
unlike($setup_helper_text, qr/\bperl\b|ZRAM_WRITEBACK_HELPER|setup-env|snapshot/, 'zram device setup shell does not execute Perl runtime helpers');

my @expected_default_keys = qw(
  ZRAM_ENABLE ZRAM_LOG_LEVEL
  ZRAM_SWAP_DEVICE ZRAM_SYSFS ZRAM_RUNTIME_DIR ZRAM_LOCK_FILE
  ZRAM_BACKING_RAW_DEVICE ZRAM_BACKING_MAPPER_NAME ZRAM_BACKING_DEVICE ZRAM_BACKING_RESERVE_MIB
  DMCRYPT_EPHEMERAL_CIPHER DMCRYPT_EPHEMERAL_KEY_SIZE DMCRYPT_EPHEMERAL_HASH DMCRYPT_RANDOM_KEY_FILE
  ZRAM_COMPRESSION_ALGORITHM ZRAM_ALGORITHM_PARAMS
  ZRAM_TIER1_ENABLE ZRAM_TIER1_ALGORITHM ZRAM_TIER1_PRIORITY ZRAM_TIER1_LEVEL
  ZRAM_TIER2_ENABLE ZRAM_TIER2_ALGORITHM ZRAM_TIER2_PRIORITY ZRAM_TIER2_LEVEL
  ZRAM_TIER3_ENABLE ZRAM_TIER3_ALGORITHM ZRAM_TIER3_PRIORITY ZRAM_TIER3_LEVEL
  ZRAM_SWAP_PRIORITY ZRAM_MAX_COMP_STREAMS
  ZRAM_WRITEBACK_ENABLE ZRAM_COMPRESSED_WRITEBACK ZRAM_WRITEBACK_BATCH_SIZE ZRAM_WRITEBACK_LIMIT_ENABLE
  ZRAM_PCT ZRAM_MIN_MIB ZRAM_MAX_MIB ZRAM_MEM_LIMIT_PCT ZRAM_WRITEBACK_LIMIT_PCT
  ZRAM_POLICY_CONFIG
);

for my $profile (@profiles) {
    my %env = read_env_file($profile);
    my ($zram_name) = ($env{ZRAM_SWAP_DEVICE} || '/dev/zram0') =~ m{/([^/]+)\z};
    $env{ZRAM_ENABLE} = '1';
    $env{ZRAM_SWAP_DEVICE_NAME} = $zram_name || 'zram0';
    $env{ZRAM_SYSFS} = "/sys/block/$env{ZRAM_SWAP_DEVICE_NAME}";
    $env{ZRAM_RUNTIME_DIR} = '/run/zram';
    $env{ZRAM_LOCK_FILE} = '/run/zram/zram-writeback.lock';
    $env{ZRAM_BACKING_RAW_PARTUUID} = '11111111-2222-3333-4444-555555555555';
    $env{ZRAM_BACKING_RAW_DEVICE} = '/dev/nvme0n1p12';
    $env{ZRAM_BACKING_DEVICE} = '/dev/mapper/zram-writeback';
    $env{ZRAM_BACKING_MAPPER_NAME} = 'zram-writeback';
    $env{ZRAM_BACKING_RESERVE_MIB} = '128';
    $env{DMCRYPT_EPHEMERAL_CIPHER} = 'aes-xts-plain64';
    $env{DMCRYPT_EPHEMERAL_KEY_SIZE} = '512';
    $env{DMCRYPT_EPHEMERAL_HASH} = 'sha256';
    $env{DMCRYPT_RANDOM_KEY_FILE} = '/dev/urandom';
    $env{ZRAM_SETUP_UNIT} = 'zram-setup.service';
    $env{FILE_ZRAM_DEFAULT} = '/etc/default/zram-writeback';
    $env{FILE_ZRAM_CONFIG} = '/etc/zram-writeback.conf';
    $env{FILE_ZRAM_SETUP_HELPER} = '/usr/local/sbin/zram-device-setup';
    $env{FILE_ZRAM_WRITEBACK_HELPER} = '/usr/local/sbin/zram-writeback';
    $env{ZRAM_POLICY_CONFIG} = '/etc/zram-writeback.conf';
    $env{ZRAM_MAINTENANCE_IO_WRITE_BANDWIDTH_MAX} = '16M';
    $env{ZRAM_MAINTENANCE_MEMORY_HIGH} = '128M';
    $env{ZRAM_MAINTENANCE_MEMORY_MAX} = '256M';
    $env{ZRAM_IDLE_WRITEBACK_INTERVAL} = '15min';
    $env{ZRAM_IDLE_WRITEBACK_RANDOMIZED_DELAY} = '2min';
    $env{ZRAM_COLD_TIER_INTERVAL} = '1h';
    $env{ZRAM_COLD_TIER_RANDOMIZED_DELAY} = '5min';
    $env{ZRAM_DAEMON_ENABLE} = '1';
    $env{ZRAM_DAEMON_PSI_WINDOW_US} = '10000000';
    $env{ZRAM_DAEMON_PSI_SOME_STALL_US} = '150000';
    $env{ZRAM_DAEMON_PSI_FULL_STALL_US} = '50000';
    $env{ZRAM_DAEMON_POLL_TIMEOUT_SEC} = '10';
    $env{ZRAM_DAEMON_PRESSURE_COOLDOWN_SEC} = '120';
    $env{ZRAM_DAEMON_EMERGENCY_COOLDOWN_SEC} = '30';
    $env{ZRAM_DAEMON_RECOVERY_HYSTERESIS_SEC} = '180';

    my $rendered = $template_text;
    $rendered =~ s/__([A-Z0-9_]+)__/
        exists $env{$1} ? $env{$1} : "__$1__"
    /gex;
    my $rendered_default = $default_template_text;
    $rendered_default =~ s/__INSTALLER_([A-Z0-9_]+)__/
        exists $env{$1} ? $env{$1} : "__INSTALLER_$1__"
    /gex;
    my @rendered_units;
    for my $unit_template (@unit_templates) {
        open my $ufh, '<', $unit_template or die "open $unit_template: $!";
        my $unit_text = do { local $/; <$ufh> };
        close $ufh or die "close $unit_template: $!";
        $unit_text =~ s/__INSTALLER_([A-Z0-9_]+)__/
            exists $env{$1} ? $env{$1} : "__INSTALLER_$1__"
        /gex;
        push @rendered_units, [$unit_template, $unit_text];
    }

    unlike($rendered, qr/__[A-Z0-9_]+__/, "$profile renders every zram config placeholder");
    unlike($rendered_default, qr/__INSTALLER_[A-Z0-9_]+__/, "$profile renders every zram default placeholder");
    my @rendered_default_keys = map { /\A([A-Z0-9_]+)=/ ? $1 : () } split /\n/, $rendered_default;
    is_deeply(\@rendered_default_keys, \@expected_default_keys, "$profile renders only shell-bootstrap zram defaults");
    like($rendered_default, qr{\A# /etc/default/zram-writeback\n# Shell-sourced bootstrap configuration[.]\n# Keep this file root-owned and not world-writable[.]\n}, "$profile keeps the requested zram default header");
    like($rendered, qr/^lock_file = \Q$env{ZRAM_LOCK_FILE}\E$/m, "$profile renders the shared zram lifecycle lock path");
    unlike(
        $rendered_default,
        qr/\b(?:ZRAM_PRESSURE|ZRAM_COLD_TIER|ZRAM_IDLE_WRITEBACK|ZRAM_DAEMON|ZRAM_HOT_AGE|ZRAM_DAILY_WRITEBACK_LIMIT|ZRAM_MAINTENANCE|ZRAM_MIN_FREE_MEMORY|ZRAM_WRITEBACK_MIN_REMAINING)/,
        "$profile keeps runtime policy out of shell zram defaults"
    );
    for my $unit (@rendered_units) {
        my ($unit_template, $unit_text) = @{$unit};
        unlike($unit_text, qr/__INSTALLER_[A-Z0-9_]+__/, "$unit_template renders every systemd placeholder for $profile");
        if ($unit_template =~ /zram-setup[.]service[.]tmpl\z/) {
            unlike($unit_text, qr/ZRAM_WRITEBACK_CONFIG|zram-writeback[.]tmpl|FILE_ZRAM_WRITEBACK_HELPER/, "$unit_template stays shell-only for $profile");
            like($unit_text, qr/^After=local-fs[.]target systemd-modules-load[.]service$/m, "$unit_template does not wait for debugfs for $profile");
            like($unit_text, qr/^Before=multi-user[.]target$/m, "$unit_template completes before multi-user for $profile");
            unlike($unit_text, qr/^ConditionPathExists=\/dev\/disk\/by-partuuid\//m, "$unit_template lets the helper wait for raw backing device for $profile");
        }
        if ($unit_template =~ /zram-writeback[.]service[.]tmpl\z/) {
            like($unit_text, qr/^After=zram-setup[.]service sys-kernel-debug[.]mount$/m, "$unit_template waits for setup for $profile");
            like($unit_text, qr/^Requires=zram-setup[.]service$/m, "$unit_template requires setup for $profile");
            like($unit_text, qr/^EnvironmentFile=\/etc\/default\/zram-writeback$/m, "$unit_template loads shell bootstrap defaults for $profile");
            like($unit_text, qr/^ExecStart=\/usr\/local\/sbin\/zram-writeback --config \$\{ZRAM_POLICY_CONFIG\} run$/m, "$unit_template uses policy config from defaults for $profile");
            like($unit_text, qr/^ReadWritePaths=\/run\/zram$/m, "$unit_template keeps runtime writes scoped for $profile");
        }
        if ($unit_template =~ /zram-writebackd[.]service[.]tmpl\z/) {
            like($unit_text, qr/^After=zram-setup[.]service sys-kernel-debug[.]mount$/m, "$unit_template waits for setup for $profile");
            like($unit_text, qr/^BindsTo=zram-setup[.]service$/m, "$unit_template is bound to setup lifecycle for $profile");
            like($unit_text, qr/^PartOf=zram-setup[.]service$/m, "$unit_template stops with setup lifecycle for $profile");
            like($unit_text, qr/^Requires=zram-setup[.]service$/m, "$unit_template requires setup for $profile");
            like($unit_text, qr/^ConditionPathExists=\/proc\/pressure\/memory$/m, "$unit_template requires PSI memory pressure support for $profile");
            like($unit_text, qr/^ExecStartPre=\/usr\/local\/sbin\/zram-writeback --config \$\{ZRAM_POLICY_CONFIG\} validate-runtime$/m, "$unit_template validates runtime before daemon start for $profile");
            like($unit_text, qr/^ExecStart=\/usr\/local\/sbin\/zram-writeback --config \$\{ZRAM_POLICY_CONFIG\} daemon$/m, "$unit_template runs the PSI daemon for $profile");
            like($unit_text, qr/^Restart=on-failure$/m, "$unit_template restarts only failed daemon exits for $profile");
            like($unit_text, qr/^TasksMax=16$/m, "$unit_template bounds daemon task fanout for $profile");
        }
        if ($unit_template =~ /zram-(?:idle-writeback|cold-tier)[.]timer[.]tmpl\z/) {
            like($unit_text, qr/^After=zram-setup[.]service$/m, "$unit_template waits for setup for $profile");
            like($unit_text, qr/^Requires=zram-setup[.]service$/m, "$unit_template requires setup for $profile");
        }
    }
    my ($fh, $path) = tempfile();
    print {$fh} $rendered;
    close $fh or die "close rendered config: $!";
    load_config($path);
    ok(eval { validate_config(require_sysfs => 0); 1 }, "$profile validates rendered zram config");
    unlink $path;
}

done_testing;
