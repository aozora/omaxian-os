#!/bin/bash
# liveboot.sh <vm> <base|full> <bios|uefi>: untouched default GRUB entry, no serial console, no network
cd /workspace/omaxian-os; VM=$1; FL=$2; MODE=$3; M=build/qemu-$VM.mon; rm -f $M
ISO=out/omaxian-$FL-0.1-trans-siberian-shaman-amd64.iso; FW=()
if [ "$MODE" = uefi ]; then cp /usr/share/OVMF/OVMF_VARS_4M.fd build/vars-$VM.fd
 FW=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -drive if=pflash,format=raw,file=build/vars-$VM.fd); fi
qemu-system-x86_64 -machine q35 -m 4096 -smp 4 -vga virtio -display none "${FW[@]}" \
 -monitor unix:$M,server,nowait -nic none -accel tcg,thread=multi \
 -cdrom $ISO -boot d -daemonize -pidfile build/qemu-$VM.pid && date +%T
