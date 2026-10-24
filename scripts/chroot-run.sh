#!/bin/bash
# chroot-run.sh <rootfs> cmd...   run a command in the build chroot with
# /proc /sys /dev mounted and a clean environment.
set -euo pipefail
R=$1; shift
for m in dev dev/pts proc sys run; do mkdir -p "$R/$m"; done
mountpoint -q "$R/dev"     || mount --bind /dev "$R/dev"
mountpoint -q "$R/dev/pts" || mount --bind /dev/pts "$R/dev/pts"
mountpoint -q "$R/proc"    || mount -t proc proc "$R/proc"
mountpoint -q "$R/sys"     || mount -t sysfs sys "$R/sys"
mountpoint -q "$R/run"     || mount -t tmpfs tmpfs "$R/run"
exec chroot "$R" /usr/bin/env -i HOME=/root TERM=dumb \
	PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
	DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LANG=C.UTF-8 "$@"
