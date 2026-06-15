#!/bin/sh
set -eu

DESTDIR=${DESTDIR:-}
PURGE=${PURGE:-0}

if [ "$(id -u)" -ne 0 ] && [ -z "$DESTDIR" ]; then
    echo "uninstall.sh must run as root unless DESTDIR is set" >&2
    exit 1
fi

if [ -z "$DESTDIR" ]; then
    systemctl disable --now zram-writebackd.service zram-writeback-pass.timer zram-writeback-budget.timer zram-writeback-setup.service 2>/dev/null || true
fi

rm -f "$DESTDIR/usr/sbin/zram-writeback"
rm -rf "$DESTDIR/usr/share/perl5/Zram/Writeback" "$DESTDIR/usr/share/perl5/Zram/Writeback.pm"
rm -f "$DESTDIR/etc/systemd/system/zram-writeback-setup.service"
rm -f "$DESTDIR/etc/systemd/system/zram-writebackd.service"
rm -f "$DESTDIR/etc/systemd/system/zram-writeback-pass.service"
rm -f "$DESTDIR/etc/systemd/system/zram-writeback-pass.timer"
rm -f "$DESTDIR/etc/systemd/system/zram-writeback-budget.service"
rm -f "$DESTDIR/etc/systemd/system/zram-writeback-budget.timer"
rm -f "$DESTDIR/usr/share/man/man8/zram-writeback.8"
rm -rf "$DESTDIR/usr/share/doc/zram-writeback"

if [ "$PURGE" = "1" ]; then
    rm -f "$DESTDIR/etc/zram-writeback.conf"
    rm -f "$DESTDIR/etc/default/zram-writeback"
    rm -f "$DESTDIR/etc/modules-load.d/zram-writeback.conf"
    rm -f "$DESTDIR/etc/modprobe.d/zram-writeback.conf"
    rm -f "$DESTDIR/etc/tmpfiles.d/zram-writeback.conf"
    rm -rf "$DESTDIR/var/lib/zram-writeback" "$DESTDIR/run/zram-writeback"
fi

if [ -z "$DESTDIR" ]; then
    systemctl daemon-reload || true
fi
