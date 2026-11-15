#!/bin/bash
# Build/fetch ALL Omaxian community-apps (every community-apps/<id>/ that ships
# an install.sh) into build/cache/community-apps/home (a partial home: .local/…
# and .config/i3/config.d/…). Rust/GPUI apps use upstream prebuilt release
# assets (disktree, omarchy-meeting-recorder); every other app (Qt 6.8 Quick:
# folio, monologue, omacalc, omacut, omawrite, plain, signed, …) is built from
# the pinned tree with its own install.sh --skip-apt. Needs Qt 6.8 dev
# packages matching Devuan Excalibur (Debian trixie host or Devuan chroot).
#
#   build-community-apps.sh [omaxian-src]
#   COMMUNITY_APPS_SKIP="omacut plain" build-community-apps.sh   # opt out
#
# Does NOT install community-plugins.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
KEY_ONLY=0; [ "${1:-}" = --key ] && { KEY_ONLY=1; shift; }
SRC=$(realpath "${1:-${OMX:-$BUILDDIR/src/omaxian}}")
# Cache key: Omaxian commit + this builder + our compat patches.
ca_key() {
	{ git -C "$SRC" rev-parse HEAD 2>/dev/null || cat "$SRC/version"
	  echo "${COMMUNITY_APPS_SKIP:-}"
	  cat "$0" "$TOPDIR"/patches/community-apps/*/*.patch 2>/dev/null; } | sha256sum | cut -c1-16
}
if [ "$KEY_ONLY" = 1 ]; then ca_key; exit 0; fi
APPS="$SRC/community-apps"
OUT="$BUILDDIR/cache/community-apps/home"
CACHE="$BUILDDIR/cache/community-apps"
mkdir -p "$CACHE" "$OUT/.local" "$OUT/.config/i3/config.d"

die() { echo "error: $*" >&2; exit 1; }
need_dir() { [ -d "$1" ] || die "missing $1 (need Omaxian v1.1+ community-apps)"; }

need_dir "$APPS"
# Every app dir with an install.sh is a default app (enumerated, not hardcoded).
mapfile -t ALL_APPS < <(find "$APPS" -mindepth 2 -maxdepth 2 -name install.sh -printf '%h\n' \
	| xargs -r -n1 basename | sort)
APPS_LIST=()
for a in "${ALL_APPS[@]}"; do
	case " ${COMMUNITY_APPS_SKIP:-} " in *" $a "*) warn "community-apps: skipping $a (COMMUNITY_APPS_SKIP)"; continue ;; esac
	APPS_LIST+=("$a")
done
# Must exist: the installer offers Folio, and the 0.1 apps must not vanish.
for a in disktree folio monologue omarchy-meeting-recorder signed; do
	need_dir "$APPS/$a"
done
msg "community-apps: ${APPS_LIST[*]}"
rm -rf "$OUT"
mkdir -p "$OUT/.local" "$OUT/.config/i3/config.d"
want() { case " ${APPS_LIST[*]} " in *" $1 "*) return 0 ;; esac; return 1; }

# --- disktree: prefer tobi/disktree release tarball (GPUI; rustc 1.97) ---
DISKTREE_VER=0.11.0
DISKTREE_URL="https://github.com/tobi/disktree/releases/download/v${DISKTREE_VER}/disktree-${DISKTREE_VER}-x86_64-linux.tar.gz"
DISKTREE_SHA256="${DISKTREE_SHA256:-7e75afa2283c8b4f9290d52eadbfc00d9f14c13aed2d224ccdf0f7826fcc05b2}"
if want disktree; then
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
fi

# --- omarchy-meeting-recorder: upstream release via install.sh --binary ---
if want omarchy-meeting-recorder; then
msg "community-apps: omarchy-meeting-recorder (prebuilt --binary)"
# install.sh refuses root and uses $HOME; run as the invoking user
env -i PATH="/usr/bin:/bin:$PATH" HOME="$OUT" USER="${USER:-omaxian}" LANG=C.UTF-8 \
	bash "$APPS/omarchy-meeting-recorder/install.sh" --skip-apt --binary \
	> "$CACHE/meeting-recorder-install.log" 2>&1 \
	|| { cat "$CACHE/meeting-recorder-install.log"; die "meeting-recorder --binary failed"; }
# Do NOT enable the bar plugin (community-plugins stay out); i3 float rules are fine.
fi

# --- everything else: the app's own install.sh (Qt 6.8, CMake or qmake6) ---
build_qt_app() {
	local name=$1
	local dir="$APPS/$name"
	command -v qmake6 >/dev/null || die "qmake6 required to build $name (run inside Devuan chroot or install Qt 6.8)"
	msg "community-apps: $name (source build)"
	# Build from a scratch copy (install.sh builds in-tree) and apply our
	# local compat patches from patches/community-apps/<app>/*.patch.
	rm -rf "$CACHE/src/$name"
	mkdir -p "$CACHE/src"
	cp -a "$APPS/$name" "$CACHE/src/$name"
	rm -rf "$CACHE/src/$name/build"
	dir="$CACHE/src/$name"
	# Build only the app target: upstream test targets use Qt >= 6.9 APIs
	# (QDragEnterEvent ctor, QQmlPropertyMap::create) absent from Qt 6.8.
	if [ -f "$dir/bin/build" ]; then
		sed -i -E 's|^(\s*cmake --build "\$BUILD_DIR" -j"\$JOBS")\s*$|\1 --target '"$name"'|' "$dir/bin/build"
	fi
	local pf
	for pf in "$TOPDIR/patches/community-apps/$name"/*.patch; do
		[ -f "$pf" ] || continue
		msg "community-apps: $name: patch $(basename "$pf")"
		patch -d "$dir" -p1 --forward --batch < "$pf" >/dev/null
	done
	# install.sh refuses root; --skip-apt assumes deps already present
	env -i PATH="/usr/bin:/bin:$PATH" HOME="$OUT" USER="${USER:-omaxian}" LANG=C.UTF-8 \
		bash "$dir/install.sh" --skip-apt \
		> "$CACHE/${name}-install.log" 2>&1 \
		|| { cat "$CACHE/${name}-install.log"; die "$name install.sh failed"; }
}

BUILT=()
for a in "${APPS_LIST[@]}"; do
	case $a in
	disktree|omarchy-meeting-recorder) ;;
	*) build_qt_app "$a" ;;
	esac
	BUILT+=("$a")
done

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
# QML smoke test (offscreen): catch Qt >= 6.9-only QML that compiles but
# fails to load on Excalibur's Qt 6.8 (e.g. "non-existent property").
if [ "${COMMUNITY_APPS_SMOKE:-1}" = 1 ]; then
	SM=$(mktemp -d /tmp/omaxian-ca-smoke.XXXXXX)
	mkdir -m700 "$SM/run"
	for a in "${BUILT[@]}"; do
		case $a in disktree|omarchy-meeting-recorder) continue ;; esac
		arg=(); [ "$a" = signed ] && arg=(open)
		env -i PATH="/usr/bin:/bin" HOME="$SM" XDG_RUNTIME_DIR="$SM/run" LANG=C.UTF-8 \
			QT_QPA_PLATFORM=offscreen timeout 8 "$OUT/.local/bin/$a" "${arg[@]}" \
			> "$CACHE/$a-smoke.log" 2>&1 || true
		if grep -E 'non-existent property|failed to load component|is not a type|module "[^"]+" is not installed|Type [A-Za-z]+ unavailable' \
			"$CACHE/$a-smoke.log"; then
			rm -rf "$SM"; die "community-apps: $a QML does not load on this Qt (see $CACHE/$a-smoke.log)"
		fi
		msg "community-apps: $a QML loads (offscreen)"
	done
	rm -rf "$SM"
fi
# Every app must have produced a launcher + desktop entry.
for a in "${BUILT[@]}"; do
	[ -e "$OUT/.local/bin/$a" ] || die "community-apps: $a produced no ~/.local/bin/$a"
	compgen -G "$OUT/.local/share/applications/*${a%%-*}*.desktop" >/dev/null \
		|| die "community-apps: $a installed no desktop entry"
done
printf '%s\n' "${BUILT[@]}" > "$CACHE/installed.txt"
ca_key > "$CACHE/stamp"
# build trees are large; the stage is what we keep
[ "${COMMUNITY_APPS_KEEP_SRC:-0}" = 1 ] || rm -rf "$CACHE/src"
ls -la "$OUT/.local/bin" || true
