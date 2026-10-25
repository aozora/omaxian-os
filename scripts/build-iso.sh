#!/bin/bash
# Build a hybrid BIOS + UEFI live ISO from a rootfs.   (run as root)
#   build-iso.sh base|full   -> $OUTDIR/omaxian-<flavor>-<version>-amd64.iso
. "$(dirname "$0")/lib.sh"
[ "$(id -u)" -eq 0 ] || die "run as root"
need mksquashfs grub-mkrescue xorriso mformat
FLAVOR=${1:-base}
R="$BUILDDIR/rootfs-$FLAVOR"
[ -e "$R.stamps/finalize" ] || [ -e "$R.stamps/full" ] || die "rootfs $FLAVOR not finished"
V=$(echo "$OMAXIAN_VERSION" | tr '~' '-')
ISO="$OUTDIR/omaxian-$FLAVOR-$V-$OMAXIAN_CODENAME_ID-$ARCH.iso"
IMG="$BUILDDIR/iso-$FLAVOR"; rm -rf "$IMG"; mkdir -p "$IMG/live" "$IMG/boot/grub" "$IMG/.disk"
"$TOPDIR/scripts/umount-chroot.sh" "$R" >/dev/null 2>&1 || true

msg "kernel + initrd"
K=$(ls "$R"/boot/vmlinuz-* | sort -V | tail -1); KV=${K##*/vmlinuz-}
cp "$K" "$IMG/live/vmlinuz"; cp "$R/boot/initrd.img-$KV" "$IMG/live/initrd.img"
echo "$KV" > "$IMG/live/kernel-version"

msg "squashfs (zstd)"
mksquashfs "$R" "$IMG/live/filesystem.squashfs" -noappend -comp zstd -Xcompression-level 15 \
	-b 1M -mem "${SQUASHFS_MEM:-1G}" -processors "${SQUASHFS_CPUS:-6}" \
	-wildcards -e 'proc/*' 'sys/*' 'dev/*' 'run/*' 'tmp/*' 'var/cache/apt/archives/*.deb' >/dev/null
du -b "$IMG/live/filesystem.squashfs" | cut -f1 > "$IMG/live/filesystem.size"
(cd "$IMG/live" && sha256sum filesystem.squashfs vmlinuz initrd.img > SHA256SUMS)

msg "grub (BIOS + UEFI) with Omaxian theme"
cp -r "$R/usr/share/grub/themes/omaxian" "$IMG/boot/grub/themes-omaxian.tmp"
mkdir -p "$IMG/boot/grub/themes"; mv "$IMG/boot/grub/themes-omaxian.tmp" "$IMG/boot/grub/themes/omaxian"
cp /usr/share/grub/unicode.pf2 "$IMG/boot/grub/" 2>/dev/null || true
LABEL="Omaxian OS $OMAXIAN_VERSION ($OMAXIAN_CODENAME) $FLAVOR"
ARGS="boot=live components username=$LIVE_USER hostname=$LIVE_HOSTNAME locales=$DEFAULT_LOCALE"
cat > "$IMG/boot/grub/grub.cfg" <<EOG
set default=0
set timeout=8
insmod all_video
insmod gfxterm
insmod png
if loadfont /boot/grub/themes/omaxian/omaxian-16.pf2; then
	loadfont /boot/grub/themes/omaxian/omaxian-24.pf2
	set gfxmode=1920x1080,1280x800,1024x768,auto
	terminal_output gfxterm
	set theme=/boot/grub/themes/omaxian/theme.txt
fi
menuentry "Try or install $LABEL" --class omaxian {
	linux /live/vmlinuz $ARGS quiet splash
	initrd /live/initrd.img
}
menuentry "$LABEL - safe graphics" --class omaxian {
	linux /live/vmlinuz $ARGS nomodeset
	initrd /live/initrd.img
}
menuentry "$LABEL - load to RAM" --class omaxian {
	linux /live/vmlinuz $ARGS toram quiet splash
	initrd /live/initrd.img
}
menuentry "$LABEL - verbose boot (no splash)" --class omaxian {
	linux /live/vmlinuz $ARGS console=tty0 console=ttyS0,115200
	initrd /live/initrd.img
}
if [ "\$grub_platform" = "efi" ]; then
	menuentry "UEFI firmware settings" { fwsetup }
fi
EOG
echo "$LABEL $(date -u +%Y%m%d)" > "$IMG/.disk/info"
# iso_9660_level=3: the full squashfs is >4 GiB (ISO9660 multi-extent file);
# args after -- go to xorriso in native mode, so no mkisofs-style -iso-level.
rm -f "$ISO"
grub-mkrescue -o "$ISO" "$IMG" -- -compliance iso_9660_level=3 -volid "$(echo "OMAXIAN_${V}_${OMAXIAN_CODENAME_TAG}_$FLAVOR" | tr 'a-z.-' 'A-Z__' | cut -c1-32)" 2>&1 | grep -v '^xorriso : UPDATE' || true
[ -s "$ISO" ] || die "grub-mkrescue failed"
(cd "$OUTDIR" && sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256")
msg "ISO: $ISO ($(du -h "$ISO" | cut -f1))"
