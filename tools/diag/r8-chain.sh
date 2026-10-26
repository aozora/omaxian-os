set -o pipefail
cd /workspace/omaxian-os; export BUILD_MIRROR=http://127.0.0.1:8099/merged
echo "base rootfs $(date +%T)"; sudo -E bash scripts/build-rootfs.sh base > build/base-r8.out 2>&1 || { echo FAIL base; exit 1; }
echo "base iso $(date +%T)"; sudo -E bash scripts/build-iso.sh base > build/iso-base-r8.out 2>&1 || { echo FAIL isobase; exit 1; }
echo "full rootfs $(date +%T)"; sudo -E bash scripts/build-rootfs.sh full > build/full-r8.out 2>&1 || { echo FAIL full; exit 1; }
echo "full iso $(date +%T)"; sudo -E bash scripts/build-iso.sh full > build/iso-full-r8.out 2>&1 || { echo FAIL isofull; exit 1; }
echo "ALLDONE $(date +%T)"
