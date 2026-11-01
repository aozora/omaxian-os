set -o pipefail
# Round 14: session 1.0.6-2 (XDG user dirs), firstboot 0.2.6 (omaxian-optional, OnlyOffice class base), new payload stage (OnlyOffice in base). Re-runs omaxian/payload.
cd /workspace/omaxian-os; export BUILD_MIRROR=http://127.0.0.1:8099/merged
for s in apt-setup omaxian upgrade configure payload finalize; do sudo rm -f build/rootfs-base.stamps/$s; done; sudo rm -f build/rootfs-full.stamps/full
echo "base rootfs $(date +%T)"; sudo -E bash scripts/build-rootfs.sh base > build/base-r14.out 2>&1 || { echo FAIL base; exit 1; }
echo "base iso $(date +%T)"; sudo -E bash scripts/build-iso.sh base > build/iso-base-r14.out 2>&1 || { echo FAIL isobase; exit 1; }
echo "full rootfs $(date +%T)"; sudo -E bash scripts/build-rootfs.sh full > build/full-r14.out 2>&1 || { echo FAIL full; exit 1; }
echo "full iso $(date +%T)"; sudo -E bash scripts/build-iso.sh full > build/iso-full-r14.out 2>&1 || { echo FAIL isofull; exit 1; }
echo "ALLDONE $(date +%T)"
