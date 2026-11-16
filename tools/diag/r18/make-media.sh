#!/bin/bash
# make-media.sh: build/round18/test-media.iso (label R18TEST) = media/ + pinned.sha256,
# the sha256 of every community app's binary inside its verified pinned tarball.
set -euo pipefail
cd /workspace/omaxian-os; D=build/round18; A=build/src/omaxian/community-apps; DL=build/cache/community-apps/dl
mkdir -p $D; T=$(mktemp -d); cp tools/diag/r18/media/* $T/
for m in $A/*/.omaxian-prebuilt; do a=$(basename $(dirname $m))
	url=$(awk -F= '$1=="url"{sub(/^[^=]*=/,"");print}' $m); sha=$(awk -F= '$1=="sha256"{print $2}' $m); bin=$(awk -F= '$1=="bin"{print $2}' $m)
	f=$DL/$a--$(basename $url); echo "$sha  $f" | sha256sum -c --quiet
	x=$(mktemp -d); tar -xzf $f -C $x; echo "$(sha256sum $x/$bin | cut -d' ' -f1) $a" >> $T/pinned.sha256; rm -rf $x
done
cat $T/pinned.sha256
xorriso -as mkisofs -quiet -V R18TEST -r -J -o $D/test-media.iso $T; rm -rf $T; ls -l $D/test-media.iso
