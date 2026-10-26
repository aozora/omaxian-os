set -o pipefail
# Round 11b: steering (Strata 1.1.1, Omaxian shell v1.0.4, Telegram Flatpak) on top of omaxian-base 0.1.7. Same stages as r11-chain.sh.
cd /workspace/omaxian-os; export BUILD_MIRROR=http://127.0.0.1:8099/merged
for s in apt-setup upgrade configure finalize; do sudo rm -f build/rootfs-base.stamps/$s; done; sudo rm -f build/rootfs-full.stamps/full
echo "base rootfs $(date +%T)"; sudo -E bash scripts/build-rootfs.sh base > build/base-r11b.out 2>&1 || { echo FAIL base; exit 1; }
echo "base iso $(date +%T)"; sudo -E bash scripts/build-iso.sh base > build/iso-base-r11b.out 2>&1 || { echo FAIL isobase; exit 1; }
echo "full rootfs $(date +%T)"; sudo -E bash scripts/build-rootfs.sh full > build/full-r11b.out 2>&1 || { echo FAIL full; exit 1; }
echo "full iso $(date +%T)"; sudo -E bash scripts/build-iso.sh full > build/iso-full-r11b.out 2>&1 || { echo FAIL isofull; exit 1; }
echo "ALLDONE $(date +%T)"
