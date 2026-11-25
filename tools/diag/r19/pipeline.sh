#!/bin/bash
# 0.3 "Space Cat" (round 19) resumable build. Each stage writes a marker into
# .r19-state ("STAGE <name> DONE"); rerunning skips finished stages. Run detached:
#   setsid nohup bash tools/diag/r19/pipeline.sh > build/round19/pipeline.out 2>&1 < /dev/null &
set -euo pipefail
cd /workspace
S=.r19-state L=build/round19 V=0.3
mkdir -p $L out/$V/debs build/r19
export OUTDIR=$PWD/out/$V LOCALREPO=$PWD/build/r19/repo
# squashfs memory cap from the round 17/18 box; this host reaches Devuan
# and GitHub directly, so no apt https proxy.
export SQUASHFS_CPUS=4 SQUASHFS_MEM=1G JOBS=4 MAKEFLAGS=-j4 CMAKE_BUILD_PARALLEL_LEVEL=4
unset COMMUNITY_APPS_STALE_OK OMAXIAN_BUILD_HTTPS_PROXY
done_() { grep -qx "STAGE $1 DONE" $S 2>/dev/null; }
mark() { echo "STAGE $1 DONE" >> $S; echo "   $(date '+%F %T %Z') $1 finished; $(df -h / | awk 'NR==2{print $4}') free, $(free -h | awk '/Mem/{print $7}') mem avail" >> $S; }
run() { local n=$1; shift; done_ $n && { echo "skip $n"; return 0; }
	echo "   $(date '+%F %T %Z') $n started" >> $S
	"$@" > $L/$n.log 2>&1 || { echo "STAGE $n FAILED $(date '+%T') (see $L/$n.log)" >> $S; exit 1; }
	mark $n; }
# Every omaxian-* package, plus the pinned chezmoi and mygo-music debs that
# fetch-third-party.sh drops into out/debs. Nothing is reused from 0.2.1:
# this host does not have that repo.
st_packages() { BUILDDIR=$PWD/build bash scripts/build-packages.sh; }
st_repo() { BUILDDIR=$PWD/build bash scripts/make-repo.sh; }
st_rootfs_base() { sudo rm -rf build/rootfs-base.stamps build/rootfs-full.stamps
	sudo env OUTDIR=$OUTDIR LOCALREPO=$LOCALREPO MAKEFLAGS=-j4 bash scripts/build-rootfs.sh base; }
st_iso_base() { sudo env OUTDIR=$OUTDIR SQUASHFS_CPUS=4 SQUASHFS_MEM=1G bash scripts/build-iso.sh base; }
st_rootfs_full() { local i
	for i in 1 2 3; do sudo rm -rf build/rootfs-full.stamps
		sudo env OUTDIR=$OUTDIR LOCALREPO=$LOCALREPO bash scripts/build-rootfs.sh full > $L/rootfs_full.try$i.log 2>&1 || { tail -20 $L/rootfs_full.try$i.log; continue; }
		grep -q 'flatpaks NOT preinstalled' $L/rootfs_full.try$i.log || return 0
		echo "try $i: flatpak missing, retrying"; done; return 1; }
st_iso_full() { sudo env OUTDIR=$OUTDIR SQUASHFS_CPUS=4 SQUASHFS_MEM=1G bash scripts/build-iso.sh full; }
st_sha() { (cd out/$V && sha256sum *.iso | tee SHA256SUMS); cp -a out/$V/*.iso out/$V/*.sha256 out/$V/SHA256SUMS "$L/" 2>/dev/null || true; }
run packages st_packages
run repo st_repo
run rootfs_base st_rootfs_base
run iso_base st_iso_base
run rootfs_full st_rootfs_full
run iso_full st_iso_full
run sha st_sha
echo "PIPELINE COMPLETE $(date '+%F %T %Z')" >> $S
