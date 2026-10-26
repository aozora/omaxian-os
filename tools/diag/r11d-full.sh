set -o pipefail
# Round 11c follow-up: rebuild only the full rootfs + ISO (optional pool pruning), base ISO from r11c kept.
cd /workspace/omaxian-os; export BUILD_MIRROR=http://127.0.0.1:8099/merged
sudo rm -f build/rootfs-full.stamps/full
echo "full rootfs $(date +%T)"; sudo -E bash scripts/build-rootfs.sh full > build/full-r11d.out 2>&1 || { echo FAIL full; exit 1; }
echo "full iso $(date +%T)"; sudo -E bash scripts/build-iso.sh full > build/iso-full-r11d.out 2>&1 || { echo FAIL isofull; exit 1; }
echo "ALLDONE $(date +%T)"
