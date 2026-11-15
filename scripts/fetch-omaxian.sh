#!/bin/bash
# Vendor the Omaxian shell (OMAXIAN_SHELL_REF) and the Omarchy upstream it pins.
#   fetch-omaxian.sh            -> $BUILDDIR/src/omaxian (+ omarchy-quattro/)
# OMAXIAN_LOCAL_SRC=/path/to/omaxian/checkout   use a local git clone (no network
#                                               needed for the Omaxian part)
. "$(dirname "$0")/lib.sh"
need git
DEST="$BUILDDIR/src/omaxian"
SRC_URL="${OMAXIAN_LOCAL_SRC:-$OMAXIAN_SHELL_REPO}"
URL=$( [ -d "$SRC_URL" ] && echo "file://$SRC_URL" || echo "$SRC_URL")
PIN="${OMAXIAN_SHELL_COMMIT:-}"
vendored_ok() {
	[ -d "$DEST/.git" ] || return 1
	[ "$(cat "$DEST/.omaxian-shell-ref" 2>/dev/null)" = "$OMAXIAN_SHELL_REF" ] || return 1
	[ -z "$PIN" ] || [ "$(git -C "$DEST" rev-parse HEAD)" = "$PIN" ]
}
if vendored_ok; then
	msg "omaxian $OMAXIAN_SHELL_REF already vendored ($(git -C "$DEST" rev-parse --short HEAD))"
else
	rm -rf "$DEST"; mkdir -p "$DEST"
	# Resolve the tag (peeled) on the remote; it may not be pushed yet.
	tagc=$(git ls-remote "$URL" "refs/tags/$OMAXIAN_SHELL_REF^{}" "refs/tags/$OMAXIAN_SHELL_REF" \
		| awk '{print $1}' | tail -1)
	if [ -n "$tagc" ] && [ -n "$PIN" ] && [ "$tagc" != "$PIN" ]; then
		die "omaxian tag $OMAXIAN_SHELL_REF is $tagc, expected OMAXIAN_SHELL_COMMIT=$PIN"
	fi
	want=${tagc:-$PIN}
	[ -n "$want" ] || die "omaxian $OMAXIAN_SHELL_REF: no such tag and no OMAXIAN_SHELL_COMMIT pin"
	[ -n "$tagc" ] || warn "omaxian tag $OMAXIAN_SHELL_REF not on $SRC_URL yet: using pinned commit $PIN"
	msg "fetching omaxian $OMAXIAN_SHELL_REF ($want) from $SRC_URL"
	git -C "$DEST" init -q
	git -C "$DEST" remote add origin "$URL"
	git -C "$DEST" fetch -q --filter=blob:none origin main "$want"
	git -C "$DEST" -c advice.detachedHead=false checkout -q --detach "$want"
	git -C "$DEST" merge-base --is-ancestor "$want" FETCH_HEAD 2>/dev/null \
		|| git -C "$DEST" merge-base --is-ancestor "$want" "$(git -C "$DEST" ls-remote origin refs/heads/main | cut -f1)" \
		|| die "omaxian $want is not on main"
	v=$(tr -d '[:space:]' < "$DEST/version" 2>/dev/null || true)
	[ "$v" = "$OMAXIAN_SHELL_REF" ] || die "omaxian $want has version '$v', expected $OMAXIAN_SHELL_REF"
	echo "$OMAXIAN_SHELL_REF" > "$DEST/.omaxian-shell-ref"
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
echo "$OMAXIAN_SHELL_REF" > "$BUILDDIR/src/omaxian.ref"; git -C "$DEST" rev-parse HEAD > "$BUILDDIR/src/omaxian.commit"; echo "$ref" > "$BUILDDIR/src/omarchy.ref"
msg "vendored omaxian $OMAXIAN_SHELL_REF + omarchy $ref -> $DEST"
