#!/bin/bash
# umount-chroot.sh <rootfs>   undo chroot-run.sh mounts (deepest first)
R=$(realpath "$1")
for m in $(awk -v r="$R" '$2 ~ "^"r"/" {print $2}' /proc/mounts | sort -r); do umount -l "$m" || true; done
