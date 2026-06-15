# Kernel configuration checklist

Target: Debian Trixie with XanMod/Linux kernel >= 7.0 and zram writeback/recompression policy.

## Required

```text
CONFIG_SWAP=y

CONFIG_ZRAM=m
# or CONFIG_ZRAM=y

CONFIG_ZSMALLOC=y

CONFIG_ZRAM_BACKEND_LZ4=y
CONFIG_ZRAM_BACKEND_LZO=y
CONFIG_ZRAM_BACKEND_ZSTD=y

CONFIG_ZRAM_DEF_COMP_LZ4=y
CONFIG_ZRAM_DEF_COMP="lz4"

CONFIG_ZRAM_MULTI_COMP=y
CONFIG_ZRAM_WRITEBACK=y
CONFIG_ZRAM_TRACK_ENTRY_ACTIME=y

CONFIG_PSI=y
```

## Strongly recommended

```text
CONFIG_DEBUG_FS=y
CONFIG_ZRAM_MEMORY_TRACKING=y
CONFIG_ZSMALLOC_STAT=y
CONFIG_IKCONFIG=y
CONFIG_IKCONFIG_PROC=y
CONFIG_CGROUPS=y
CONFIG_MEMCG=y
```

## Optional

```text
CONFIG_ZRAM_BACKEND_LZ4HC=y
CONFIG_ZSWAP=y
CONFIG_ZSWAP_DEFAULT_ON=n
CONFIG_ZSMALLOC_CHAIN_SIZE=8
```

Use `CONFIG_ZSMALLOC_CHAIN_SIZE=16` only after workload testing. Larger chains can improve density for some data but may hurt under internal fragmentation.

## Verification

```sh
zgrep -E 'CONFIG_(ZRAM|ZSMALLOC|PSI|SWAP|ZSWAP|IKCONFIG|MEMCG)' /proc/config.gz \
  || grep -E 'CONFIG_(ZRAM|ZSMALLOC|PSI|SWAP|ZSWAP|IKCONFIG|MEMCG)' /boot/config-"$(uname -r)"
```
