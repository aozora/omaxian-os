#!/bin/bash
# Boot an ISO (or an installed disk) in QEMU and take screenshots.
#   boot-test.sh <iso> [uefi|bios] [seconds] [shot-prefix]
# Env: ACCEL=tcg|kvm (default tcg: KVM hangs on the build box), RAM=3584,
#      DISK=path.qcow2 (attach/create a disk for installer tests),
#      BOOT=d|c (cdrom or disk), INTERVAL=60 (seconds between shots)
# QEMU monitor socket: $BUILDDIR/qemu-<prefix>.mon  (send keys with tools/qmon.py)
. "$(dirname "$0")/lib.sh"
need qemu-system-x86_64
ISO=${1:-}; FW=${2:-uefi}; SECS=${3:-900}; P=${4:-$FW}
ACCEL=${ACCEL:-tcg}; RAM=${RAM:-3584}; INTERVAL=${INTERVAL:-60}; BOOT=${BOOT:-d}
SHOTS="$TOPDIR/shots"; mkdir -p "$SHOTS"
MON="$BUILDDIR/qemu-$P.mon"; SER="$BUILDDIR/qemu-$P.serial.log"; rm -f "$MON"
A=(-machine q35 -m "$RAM" -smp 4 -vga virtio -display none
   -monitor unix:"$MON",server,nowait -serial file:"$SER"
   -netdev user,id=n0 -device virtio-net-pci,netdev=n0
   -device intel-hda -device hda-duplex -usb -device usb-tablet)
if [ "$ACCEL" = kvm ]; then A+=(-accel kvm -cpu host); else A+=(-accel tcg,thread=multi -cpu max); fi
if [ "$FW" = uefi ]; then
	cp /usr/share/OVMF/OVMF_VARS_4M.fd "$BUILDDIR/ovmf-vars-$P.fd" 2>/dev/null || true
	A+=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd
	    -drive if=pflash,format=raw,file="$BUILDDIR/ovmf-vars-$P.fd")
fi
[ -n "$ISO" ] && A+=(-drive file="$ISO",media=cdrom,if=none,id=cd0,readonly=on -device ide-cd,drive=cd0,bootindex=$([ "$BOOT" = d ] && echo 0 || echo 2))
if [ -n "${DISK:-}" ]; then
	[ -e "$DISK" ] || qemu-img create -f qcow2 "$DISK" 30G >/dev/null
	A+=(-drive file="$DISK",if=none,id=hd0 -device virtio-blk-pci,drive=hd0,bootindex=$([ "$BOOT" = c ] && echo 0 || echo 1))
fi
msg "qemu ($ACCEL, $FW, ${RAM}M) for ${SECS}s; shots every ${INTERVAL}s -> $SHOTS/$P-*.png"
qemu-system-x86_64 "${A[@]}" & QPID=$!
shot() { python3 "$TOPDIR/tools/qmon.py" "$MON" screendump "$SHOTS/$P-$1.png" >/dev/null 2>&1 || true; }
t=0
while kill -0 $QPID 2>/dev/null && [ $t -lt "$SECS" ]; do
	sleep "$INTERVAL"; t=$((t+INTERVAL)); shot "$(printf %04d $t)s"
done
[ "${KEEP:-0}" = 1 ] && { msg "VM left running (pid $QPID, monitor $MON)"; exit 0; }
kill $QPID 2>/dev/null || true
msg "done; serial log: $SER"
