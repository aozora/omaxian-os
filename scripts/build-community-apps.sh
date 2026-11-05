#!/bin/bash
# Build/fetch the four default community-apps into build/cache/community-apps/home
# (a partial home: .local/… and .config/i3/config.d/…). Prefer upstream prebuilt
# release assets for Rust/GPUI apps; build Qt apps (monologue, signed) when
# qmake6 is available (typically inside the Devuan rootfs chroot).
#
#   build-community-apps.sh [omaxian-src]
#
# Does NOT install community-plugins.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
SRC=$(realpath "${1:-${OMX:-$BUILDDIR/src/omaxian}}")
APPS="$SRC/community-apps"
OUT="$BUILDDIR/cache/community-apps/home"
CACHE="$BUILDDIR/cache/community-apps"
mkdir -p "$CACHE" "$OUT/.local" "$OUT/.config/i3/config.d"

die() { echo "error: $*" >&2; exit 1; }
need_dir() { [ -d "$1" ] || die "missing $1 (need Omaxian v1.1+ community-apps)"; }

need_dir "$APPS/disktree"
need_dir "$APPS/monologue"
need_dir "$APPS/omarchy-meeting-recorder"
need_dir "$APPS/signed"

# --- disktree: prefer tobi/disktree release tarball (GPUI; rustc 1.97) ---
DISKTREE_VER=0.11.0
DISKTREE_URL="https://github.com/tobi/disktree/releases/download/v${DISKTREE_VER}/disktree-${DISKTREE_VER}-x86_64-linux.tar.gz"
DISKTREE_SHA256="${DISKTREE_SHA256:-7e75afa2283c8b4f9290d52eadbfc00d9f14c13aed2d224ccdf0f7826fcc05b2}"
msg "community-apps: disktree ${DISKTREE_VER} (prebuilt)"
DT_TGZ="$CACHE/disktree-${DISKTREE_VER}-x86_64-linux.tar.gz"
if [ ! -f "$DT_TGZ" ] || ! echo "$DISKTREE_SHA256  $DT_TGZ" | sha256sum -c --status; then
	curl -fsSL "$DISKTREE_URL" -o "$DT_TGZ"
	echo "$DISKTREE_SHA256  $DT_TGZ" | sha256sum -c
fi
rm -rf "$CACHE/disktree-extract"
mkdir -p "$CACHE/disktree-extract"
tar -xzf "$DT_TGZ" -C "$CACHE/disktree-extract"
# upstream release install.sh embeds absolute PREFIX; install then rewrite desktop Exec
(
	export HOME="$OUT" PREFIX="$OUT/.local"
	bash "$CACHE/disktree-extract"/disktree-*/install.sh
)
install -m644 "$APPS/disktree/omaxian/i3-disktree.conf" \
	"$OUT/.config/i3/config.d/90_disktree.conf"

# --- omarchy-meeting-recorder: upstream release via install.sh --binary ---
msg "community-apps: omarchy-meeting-recorder (prebuilt --binary)"
# install.sh refuses root and uses $HOME; run as the invoking user
env -i PATH="/usr/bin:/bin:$PATH" HOME="$OUT" USER="${USER:-omaxian}" LANG=C.UTF-8 \
	bash "$APPS/omarchy-meeting-recorder/install.sh" --skip-apt --binary \
	> "$CACHE/meeting-recorder-install.log" 2>&1 \
	|| { cat "$CACHE/meeting-recorder-install.log"; die "meeting-recorder --binary failed"; }
# Do NOT enable the bar plugin (community-plugins stay out); i3 float rules are fine.

# --- monologue + signed: qmake6 build ---
build_qt_app() {
	local name=$1
	local dir="$APPS/$name"
	command -v qmake6 >/dev/null || die "qmake6 required to build $name (run inside Devuan chroot or install Qt 6.8)"
	msg "community-apps: $name (qmake6 build)"
	# install.sh refuses root; --skip-apt assumes deps already present
	env -i PATH="/usr/bin:/bin:$PATH" HOME="$OUT" USER="${USER:-omaxian}" LANG=C.UTF-8 \
		bash "$dir/install.sh" --skip-apt \
		> "$CACHE/${name}-install.log" 2>&1 \
		|| { cat "$CACHE/${name}-install.log"; die "$name install.sh failed"; }
}

build_qt_app monologue
build_qt_app signed

# Desktop files must not embed the staging absolute path (home-template is
# copied into real $HOME). Prefer bare command names; ~/.local/bin is on PATH
# via omaxian-session / .xsessionrc.
if [ -d "$OUT/.local/share/applications" ]; then
	find "$OUT/.local/share/applications" -name '*.desktop' -print0 \
		| xargs -0 -r sed -i -E "s|$OUT/.local/bin/||g"
fi
# Guard: no leftover staging path
if grep -rIl --exclude-dir=themes "$OUT" "$OUT" 2>/dev/null | head -5 | grep -q .; then
	grep -rIl --exclude-dir=themes "$OUT" "$OUT" | head
	die "community-apps stage still contains staging path $OUT"
fi

msg "community-apps stage: $(du -sh "$OUT" | cut -f1)"
printf '%s\n' disktree monologue omarchy-meeting-recorder signed > "$CACHE/installed.txt"
ls -la "$OUT/.local/bin" || true
