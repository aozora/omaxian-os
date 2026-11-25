#!/bin/bash
# make-media.sh: build/round19/test-media.iso (label R19TEST) = media/ + pinned.sha256.
# Pinned apps: sha256 of the binary inside the verified tarball.
# flowtunes, fantasi, omarchy-local-ai: sha256 of the binary the image build
# staged (compiled once, or copied). The guest check is the same byte compare.
set -euo pipefail
cd /workspace
D=build/round19
A=build/src/omaxian/community-apps
DL=build/cache/community-apps/dl
STAGE=build/cache/community-apps/home/.local/bin
mkdir -p $D
T=$(mktemp -d)
cp tools/diag/r19/media/* $T/
: > $T/pinned.sha256
for dir in $A/*/; do
	a=$(basename "$dir")
	[ -f "$dir/install.sh" ] || continue
	if [ -f "$dir/.omaxian-prebuilt" ]; then
		url=$(awk -F= '$1=="url"{sub(/^[^=]*=/,"");print}' "$dir/.omaxian-prebuilt")
		sha=$(awk -F= '$1=="sha256"{print $2}' "$dir/.omaxian-prebuilt")
		bin=$(awk -F= '$1=="bin"{print $2}' "$dir/.omaxian-prebuilt")
		f=$DL/$a--$(basename "$url")
		echo "$sha  $f" | sha256sum -c --quiet
		x=$(mktemp -d)
		tar -xzf "$f" -C "$x"
		echo "$(sha256sum "$x/$bin" | cut -d' ' -f1) $a" >> $T/pinned.sha256
		rm -rf "$x"
	else
		[ -e "$STAGE/$a" ] || { echo "missing staged binary $a" >&2; exit 1; }
		echo "$(sha256sum "$STAGE/$a" | cut -d' ' -f1) $a" >> $T/pinned.sha256
	fi
done
cat $T/pinned.sha256
xorriso -as mkisofs -quiet -V R19TEST -r -J -o $D/test-media.iso $T
rm -rf $T
ls -l $D/test-media.iso
