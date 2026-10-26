#!/bin/bash
# inspect.sh mount|check|umount  — read-only offline inspection of build/i8.qcow2
cd /workspace/omaxian-os; IMG=build/i8.qcow2; RAW=build/i8.raw; MNT=/mnt/i8
case $1 in
mount)
  touch $RAW; sudo qemu-storage-daemon --blockdev driver=file,node-name=f,filename=$IMG,read-only=on \
   --blockdev driver=qcow2,node-name=q,file=f,read-only=on \
   --export type=fuse,id=e,node-name=q,mountpoint=$RAW,writable=off --daemonize --pidfile build/qsd-i8.pid
  sleep 2; start=$(sudo python3 -c "
import struct;f=open('$RAW','rb');f.seek(1024)
for i in range(128):
  e=f.read(128)
  if e[56:].decode('utf-16le').strip('\0') or True:
    if i==1: print(struct.unpack('<Q',e[32:40])[0]); break")
  echo p2 start $start; sudo mkdir -p $MNT; sudo mount -t ext4 -o ro,noload,loop,offset=$((start*512)) $RAW $MNT && echo mounted;;
umount)
  sudo umount $MNT; sudo kill $(sudo cat build/qsd-i8.pid) 2>/dev/null; sleep 2; mountpoint -q $RAW && sudo umount -l $RAW; rm -f $RAW; echo unmounted;;
check)
  R=$MNT; S="sudo"
  echo "== optional apps"; n=0; for p in $(cat /tmp/opt-pkgs.txt); do st=$($S chroot $R dpkg-query -W -f='${Status} ${Version}' $p 2>/dev/null); case "$st" in "install ok installed"*) n=$((n+1));; *) echo "MISSING $p [$st]";; esac; done; echo "installed $n/23"
  $S chroot $R dpkg-query -W -f='${Package} ${Version}\n' krita chromium thunderbird omaxian-firstboot omaxian-base 2>&1
  echo "== pending"; $S cat $R/var/lib/omaxian/optional-pending.list 2>&1; echo "== optional-packages.list"; $S cat $R/var/lib/omaxian/optional-packages.list 2>&1 | tr '\n' ' '; echo
  echo "== SUPPORTED"; $S ls -l $R/usr/share/i18n/SUPPORTED* 2>&1; $S md5sum $R/usr/share/i18n/SUPPORTED build/rootfs-full/usr/share/i18n/SUPPORTED.omaxian-orig 2>&1; $S grep -c "^en UTF-8" $R/usr/share/i18n/SUPPORTED; $S chroot $R dpkg-divert --list 2>/dev/null | grep -i supported || echo "no SUPPORTED diversion"
  echo "== firstboot"; $S ls -l --time-style=full-iso $R/var/lib/omaxian/; $S cat $R/var/lib/omaxian/firstboot.done 2>&1; $S tail -15 $R/var/log/omaxian-firstboot.log 2>&1
  echo "== locale"; $S cat $R/etc/default/locale $R/etc/locale.conf 2>&1; $S cat $R/home/tester/r8-locale.txt 2>&1; $S cat $R/etc/timezone
  echo "== appimages"; $S ls $R/home/tester/AppImages 2>&1 | grep -ic appimage; $S grep -c integrated $R/home/tester/.local/state/omaxian/user-firstrun.log 2>/dev/null || $S find $R/home/tester -name "user-firstrun.log" -exec grep -c integrated {} \;
  echo "== openra"; for g in ra cnc d2k; do printf "%s content " $g; $S find $R/home/tester/.config/openra/Content/$g -type f 2>/dev/null | wc -l; done; $S find $R/home/tester/.config/openra/maps -maxdepth 2 2>/dev/null
  echo "== flatpaks"; $S ls $R/var/lib/flatpak/app | tr '\n' ' '; echo; $S ls $R/var/lib/flatpak/app/us.zoom.Zoom/current 2>&1 | head -1
  echo "== live pkgs"; for p in live-boot live-config live-tools calamares omaxian-calamares-settings; do $S chroot $R dpkg-query -W -f='${Package} ${Status}\n' $p 2>/dev/null | grep -q "ok installed" && echo "STILL $p"; done; echo live check done
  $S ls $R/etc/apt/sources.list.d/ ; $S ls -d $R/var/cache/omaxian/optional-pool 2>&1;;
esac
