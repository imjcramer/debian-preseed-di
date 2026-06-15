; /etc/zram-writeback.conf
;
; Debian Trixie / XanMod >= 7.0 zram writeback policy.
; Replace backing_dev with a dedicated encrypted partition before enabling setup.
;
; The daemon writes zram sysfs directly. It does not use shell echo, and it
; serializes recompress/writeback passes with a per-device lock.

[device]
name = zram0
dev = /dev/zram0
sysfs = /sys/block/zram0
num_devices = 1

; Hot-path compressor. Must be set before disksize.
primary_algorithm = lz4

; Dedicated backing partition for zram writeback. Must be set before disksize.
; Use dm-crypt/LUKS when swapped memory may contain secrets.
backing_dev = /dev/disk/by-partuuid/REPLACE_WITH_DEDICATED_ENCRYPTED_ZRAM_WRITEBACK_PARTITION
require_backing_dev = true

; Must be set before disksize on kernels that expose this attribute.
compressed_writeback = yes
writeback_batch_size = 64

; Conservative starter values for a 64 GiB RAM system. Tune from mm_stat,
; bd_stat and /proc/pressure/memory.
disksize = 96G
mem_limit = 48G
swap_priority = 100

; zswap in front of zram usually adds an unwanted compression/cache layer.
require_zswap_disabled = true

; Safe default: do not reset an initialized swap device unless explicitly forced.
reset_if_initialized = false
mkswap = true
swapon = true

; warn = keep going if zstd level parameters are unsupported by the kernel
; fail = abort setup if any algorithm_params write fails
algorithm_param_fail_mode = warn

[runtime]
state_dir = /var/lib/zram-writeback
run_dir = /run/zram-writeback
default_interval_sec = 60
jitter_sec = 0
dry_run = false
verbose = false

[secondary.1]
algorithm = lzo-rle
priority = 1
purpose = idle_reusable
params =

[secondary.2]
algorithm = zstd
priority = 2
purpose = huge_idle
params = level=6

[secondary.3]
algorithm = zstd
priority = 3
purpose = huge_nonidle
params = level=3

[idle_mark]
enabled = true
normal_idle_age_sec = 1800
pressure_idle_age_sec = 900
emergency_idle_age_sec = 300
fallback_mark_all = false

[pressure]
normal_mem_available_pct = 20
pressure_mem_available_pct = 12
emergency_mem_available_pct = 6

; PSI values are percentages from /proc/pressure/memory avg10.
recompress_psi_some_avg10 = 0.50
writeback_psi_some_avg10 = 2.00
emergency_psi_some_avg10 = 8.00
writeback_psi_full_avg10 = 0.30
emergency_psi_full_avg10 = 1.50

[writeback_budget]
enabled = true

; zram writeback_limit is counted in 4 KiB units. The daemon converts MiB.
daily_budget_mib = 768
emergency_extra_budget_mib = 1024
min_remaining_budget_pct = 10
emergency_topup_once_daily = true

[pass.idle_lzo_rle]
enabled = true
operation = recompress
type = idle
priority = 1
threshold_bytes = 2048
max_pages_normal = 65536
max_pages_pressure = 131072
max_pages_emergency = 262144
run_when = normal,pressure,emergency

[pass.huge_idle_zstd]
enabled = true
operation = recompress
type = huge_idle
priority = 2
threshold_bytes = 3000
max_pages_normal = 32768
max_pages_pressure = 65536
max_pages_emergency = 131072
run_when = normal,pressure,emergency

[pass.huge_nonidle_zstd]
enabled = true
operation = recompress
type = huge
priority = 3
threshold_bytes = 3584
max_pages_normal = 0
max_pages_pressure = 4096
max_pages_emergency = 16384
run_when = pressure,emergency

[pass.writeback_incompressible]
enabled = true
operation = writeback
type = incompressible
run_when = pressure,emergency
requires_budget = true
after_recompress = true

[pass.writeback_huge_idle]
enabled = true
operation = writeback
type = huge_idle
run_when = emergency
requires_budget = true
after_recompress = true

[pass.writeback_idle]
enabled = false
operation = writeback
type = idle
run_when = emergency
requires_budget = true
after_recompress = true

[page_index_targeting]
; Optional. Requires CONFIG_ZRAM_MEMORY_TRACKING and debugfs access.
enabled = false
block_state = /sys/kernel/debug/zram/zram0/block_state
max_ranges_per_write = 128
max_indexes_per_pass = 8192
replace_generic_writeback = false
prefer_states = n,hi
avoid_states = s,w

[compact]
after_recompress = true
after_writeback = true

[lock]
lock_file = /run/lock/zram-writeback-zram0.lock
retry_eagain = true
retry_eagain_sleep_ms = 250
retry_eagain_max = 8

[telemetry]
mm_stat = /sys/block/zram0/mm_stat
bd_stat = /sys/block/zram0/bd_stat
io_stat = /sys/block/zram0/io_stat
memory_psi = /proc/pressure/memory
zsmalloc_classes = /sys/kernel/debug/zsmalloc/zram0/classes
