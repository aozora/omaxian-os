#!/bin/bash
# Vendor the Omaxian shell (OMAXIAN_SHELL_REF) and the Omarchy upstream it pins.
#   fetch-omaxian.sh            -> $BUILDDIR/src/omaxian (+ omarchy-quattro/)
# OMAXIAN_LOCAL_SRC=/path/to/omaxian/checkout   use a local git clone (no network
#                                               needed for the Omaxian part)
. "$(dirname "$0")/lib.sh"
need git
DEST="$BUILDDIR/src/omaxian"
SRC_URL="${OMAXIAN_LOCAL_SRC:-$OMAXIAN_SHELL_REPO}"
if [ -d "$DEST/.git" ] && [ "$(git -C "$DEST" describe --tags --exact-match 2>/dev/null)" = "$OMAXIAN_SHELL_REF" ]; then
	msg "omaxian $OMAXIAN_SHELL_REF already vendored"
else
	rm -rf "$DEST"; mkdir -p "$(dirname "$DEST")"
	msg "cloning omaxian $OMAXIAN_SHELL_REF from $SRC_URL"
	git -c advice.detachedHead=false clone -q --depth 1 --branch "$OMAXIAN_SHELL_REF" \
		"$( [ -d "$SRC_URL" ] && echo "file://$SRC_URL" || echo "$SRC_URL")" "$DEST"
fi
ref="${OMARCHY_REF:-}"
if [ -z "$ref" ]; then
	ref=$(sed -n 's/^UPSTREAM_REF="\${OMARCHY_UPSTREAM_REF:-\(.*\)}"/\1/p' "$DEST/scripts/setup.sh" | head -1)
	[ -n "$ref" ] || die "cannot read UPSTREAM_REF from omaxian scripts/setup.sh"
fi
OQ="$DEST/omarchy-quattro"
if [ -e "$OQ/.git" ] && [ "$(cat "$OQ/.omaxian-ref" 2>/dev/null)" = "$ref" ]; then
	msg "omarchy $ref already present"
else
	msg "cloning omarchy $ref"
	rm -rf "$OQ" "$OQ.tmp"
	git -c advice.detachedHead=false clone -q --depth 1 --branch "$ref" "$OMARCHY_REPO" "$OQ.tmp"
	mv "$OQ.tmp" "$OQ"; echo "$ref" > "$OQ/.omaxian-ref"
fi
[ -d "$OQ/themes" ] && [ -d "$OQ/default" ] || die "omarchy $ref has no themes/ or default/"
echo "$OMAXIAN_SHELL_REF" > "$BUILDDIR/src/omaxian.ref"; echo "$ref" > "$BUILDDIR/src/omarchy.ref"
msg "vendored omaxian $OMAXIAN_SHELL_REF + omarchy $ref -> $DEST"
