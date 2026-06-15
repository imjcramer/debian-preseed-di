#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESTDIR=${DESTDIR:-}

need_root() {
    if [ "$(id -u)" -ne 0 ] && [ -z "$DESTDIR" ]; then
        echo "install.sh must run as root unless DESTDIR is set" >&2
        exit 1
    fi
}

install_config() {
    src=$1
    dst=$2
    mode=$3
    dir=$(dirname -- "$dst")
    install -d -m 0755 "$dir"
    if [ -e "$dst" ]; then
        install -m "$mode" "$src" "$dst.dist"
        echo "preserved existing $dst; installed $dst.dist" >&2
    else
        install -m "$mode" "$src" "$dst"
    fi
}

need_root

install -d -m 0755 "$DESTDIR/usr/sbin"
install -m 0755 "$ROOT/sbin/zram-writeback" "$DESTDIR/usr/sbin/zram-writeback"

install -d -m 0755 "$DESTDIR/usr/share/perl5"
rm -rf "$DESTDIR/usr/share/perl5/Zram/Writeback" "$DESTDIR/usr/share/perl5/Zram/Writeback.pm"
cp -a "$ROOT/lib/Zram" "$DESTDIR/usr/share/perl5/"
find "$DESTDIR/usr/share/perl5/Zram" -type d -exec chmod 0755 {} +
find "$DESTDIR/usr/share/perl5/Zram" -type f -exec chmod 0644 {} +

install_config "$ROOT/etc/zram-writeback.conf" "$DESTDIR/etc/zram-writeback.conf" 0644
install_config "$ROOT/etc/default/zram-writeback" "$DESTDIR/etc/default/zram-writeback" 0644
install_config "$ROOT/modules-load.d/zram-writeback.conf" "$DESTDIR/etc/modules-load.d/zram-writeback.conf" 0644
install_config "$ROOT/modprobe.d/zram-writeback.conf" "$DESTDIR/etc/modprobe.d/zram-writeback.conf" 0644
install_config "$ROOT/tmpfiles.d/zram-writeback.conf" "$DESTDIR/etc/tmpfiles.d/zram-writeback.conf" 0644

install -d -m 0755 "$DESTDIR/etc/systemd/system"
install -m 0644 "$ROOT/systemd/"*.service "$DESTDIR/etc/systemd/system/"
install -m 0644 "$ROOT/systemd/"*.timer "$DESTDIR/etc/systemd/system/"

install -d -m 0755 "$DESTDIR/usr/share/man/man8"
install -m 0644 "$ROOT/man/zram-writeback.8" "$DESTDIR/usr/share/man/man8/zram-writeback.8"

install -d -m 0755 "$DESTDIR/usr/share/doc/zram-writeback"
install -m 0644 "$ROOT/README.md" "$ROOT/SECURITY.md" "$DESTDIR/usr/share/doc/zram-writeback/"
cp -a "$ROOT/docs" "$DESTDIR/usr/share/doc/zram-writeback/"
find "$DESTDIR/usr/share/doc/zram-writeback" -type d -exec chmod 0755 {} +
find "$DESTDIR/usr/share/doc/zram-writeback" -type f -exec chmod 0644 {} +

if [ -z "$DESTDIR" ]; then
    systemd-tmpfiles --create /etc/tmpfiles.d/zram-writeback.conf || true
    systemctl daemon-reload || true
fi

cat >&2 <<'MSG'
Installed zram-writeback.

Next steps:
  1. Replace backing_dev in /etc/zram-writeback.conf with a dedicated partition.
  2. Run: zram-writeback validate --config /etc/zram-writeback.conf
  3. Enable either zram-writebackd.service or zram-writeback-pass.timer, not both.
MSG
