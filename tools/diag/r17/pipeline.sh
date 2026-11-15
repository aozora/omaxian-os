#!/bin/bash
# 0.2 "Space Cat" resumable build. Each stage writes a marker into .r17-state
# ("STAGE <name> DONE"); rerunning skips finished stages. Run detached:
#   setsid nohup bash tools/diag/r17/pipeline.sh > build/round17/pipeline.out 2>&1 < /dev/null &
set -euo pipefail
cd /workspace/omaxian-os
S=.r17-state L=build/round17 P=http://127.0.0.1:8791
mkdir -p $L out/0.2/debs build/r17
export OUTDIR=$PWD/out/0.2 LOCALREPO=$PWD/build/r17/repo
# resource limits (two box losses earlier): squashfs 4 threads / 1G, make -j4
export SQUASHFS_CPUS=4 SQUASHFS_MEM=1G JOBS=4 MAKEFLAGS=-j4 CMAKE_BUILD_PARALLEL_LEVEL=4
done_() { grep -qx "STAGE $1 DONE" $S; }
mark() { echo "STAGE $1 DONE" >> $S; echo "   $(date '+%F %T %Z') $1 finished; $(df -h / | awk 'NR==2{print $4}') free, $(free -h | awk '/Mem/{print $7}') mem avail" >> $S; }
run() { local n=$1; shift; done_ $n && { echo "skip $n"; return 0; }
	echo "   $(date '+%F %T %Z') $n started" >> $S
	"$@" > $L/$n.log 2>&1 || { echo "STAGE $n FAILED $(date '+%T') (see $L/$n.log)" >> $S; exit 1; }
	mark $n; }
st_packages() { BUILDDIR=$PWD/build bash scripts/build-packages.sh omaxian-base omaxian-branding omaxian-firstboot omaxian-calamares-settings omaxian-session omaxian-voxtype; }
st_reuse() { # unchanged published 0.1 debs: reuse repo-local's (signed index) bytes, never rebuild
	gpgv --keyring keys/public/omaxian-archive-keyring.pgp repo-local/dists/excalibur/InRelease
	local p f want
	for p in omaxian-fonts-nerd omaxian-strata omaxian-ydotool; do
		f=$(awk -v p=$p '/^Package:/{x=($2==p)} x&&/^Filename:/{print $2}' repo-local/dists/excalibur/main/binary-amd64/Packages)
		want=$(awk -v p=$p '/^Package:/{x=($2==p)} x&&/^SHA256:/{print $2}' repo-local/dists/excalibur/main/binary-amd64/Packages)
		echo "$want  repo-local/$f" | sha256sum -c -
		grep -q "$(sha256sum repo-local/dists/excalibur/main/binary-amd64/Packages | cut -d' ' -f1)" repo-local/dists/excalibur/InRelease
		cp repo-local/$f out/0.2/debs/
	done; }
st_repo() { BUILDDIR=$PWD/build bash scripts/make-repo.sh; }
st_rootfs_base() { sudo rm -rf build/rootfs-base.stamps build/rootfs-full.stamps
	sudo env OUTDIR=$OUTDIR LOCALREPO=$LOCALREPO OMAXIAN_BUILD_HTTPS_PROXY=$P MAKEFLAGS=-j4 bash scripts/build-rootfs.sh base; }
st_iso_base() { sudo env OUTDIR=$OUTDIR SQUASHFS_CPUS=4 SQUASHFS_MEM=1G bash scripts/build-iso.sh base; }
st_rootfs_full() { local i # retry: a Flathub timeout once left Telegram out
	for i in 1 2 3; do sudo rm -rf build/rootfs-full.stamps
		sudo env OUTDIR=$OUTDIR LOCALREPO=$LOCALREPO OMAXIAN_BUILD_HTTPS_PROXY=$P bash scripts/build-rootfs.sh full > $L/rootfs_full.try$i.log 2>&1 || { tail -20 $L/rootfs_full.try$i.log; continue; }
		grep -q 'flatpaks NOT preinstalled' $L/rootfs_full.try$i.log || return 0
		echo "try $i: flatpak missing, retrying"; done; return 1; }
st_iso_full() { sudo env OUTDIR=$OUTDIR SQUASHFS_CPUS=4 SQUASHFS_MEM=1G bash scripts/build-iso.sh full; }
st_sha() { (cd out/0.2 && sha256sum *.iso | tee SHA256SUMS.r17); }
run packages st_packages
run reuse st_reuse
run repo st_repo
run rootfs_base st_rootfs_base
run iso_base st_iso_base
run rootfs_full st_rootfs_full
run iso_full st_iso_full
run sha st_sha
echo "PIPELINE COMPLETE $(date '+%F %T %Z')" >> $S
