set -o pipefail
# Round 13: calamares-settings 0.2.13 (menu/autostart fix, input group), session 1.0.6-1, voxtype 1.1.1-3, omaxian-ydotool, easyeffects + cmatrix. Re-runs xlibre/user/omaxian for the new list entries.
cd /workspace/omaxian-os; export BUILD_MIRROR=http://127.0.0.1:8099/merged
for s in apt-setup xlibre user omaxian upgrade configure finalize; do sudo rm -f build/rootfs-base.stamps/$s; done; sudo rm -f build/rootfs-full.stamps/full
echo "base rootfs $(date +%T)"; sudo -E bash scripts/build-rootfs.sh base > build/base-r13.out 2>&1 || { echo FAIL base; exit 1; }
echo "base iso $(date +%T)"; sudo -E bash scripts/build-iso.sh base > build/iso-base-r13.out 2>&1 || { echo FAIL isobase; exit 1; }
echo "full rootfs $(date +%T)"; sudo -E bash scripts/build-rootfs.sh full > build/full-r13.out 2>&1 || { echo FAIL full; exit 1; }
echo "full iso $(date +%T)"; sudo -E bash scripts/build-iso.sh full > build/iso-full-r13.out 2>&1 || { echo FAIL isofull; exit 1; }
echo "ALLDONE $(date +%T)"
