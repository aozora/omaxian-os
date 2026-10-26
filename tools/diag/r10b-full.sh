set -o pipefail
# Round 10b: full ISO only, after the omaxian-voxtype 1.1.1-2 wrapper fix (base untouched)
cd /workspace/omaxian-os; export BUILD_MIRROR=http://127.0.0.1:8099/merged
sudo rm -f build/rootfs-full.stamps/full
echo "full rootfs $(date +%T)"; sudo -E bash scripts/build-rootfs.sh full > build/full-r10b.out 2>&1 || { echo FAIL full; exit 1; }
echo "full iso $(date +%T)"; sudo -E bash scripts/build-iso.sh full > build/iso-full-r10b.out 2>&1 || { echo FAIL isofull; exit 1; }
echo "ALLDONE $(date +%T)"
