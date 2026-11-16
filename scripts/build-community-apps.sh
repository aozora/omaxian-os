#!/bin/bash
# Stage ALL Omaxian community-apps (every community-apps/<id>/ that ships an
# install.sh) into build/cache/community-apps/home (a partial home: .local/…
# and .config/i3/config.d/…), from the pinned PRE-BUILT binaries only.
#
# Since Omaxian v1.2.0 every app carries <app>/.omaxian-prebuilt (url, sha256,
# tree, bin, arch, qt): Omaxian's CI release apps-<sha7> for the Qt/Rust apps,
# tobi/disktree's upstream release for disktree.
#
# EXCEPTION: an app with Qt 6.8 compat patches in patches/community-apps/<app>/
# is still built from source (patched). The v1.2.0 Folio and Monologue binaries
# link against Qt 6.8 but their compiled-in QML uses Qt >= 6.9 properties
# (Flickable.acceptedButtons, VideoOutput.mirrored / endOfStreamPolicy) and
# does not load on Excalibur. Drop the patch dir once upstream's pin loads on
# Qt 6.8 (the QML smoke test below proves it); that needs Qt 6.8 dev packages
# on the build host (Debian trixie host or Devuan chroot) only while any
# patched app remains.
#
#   1. read each manifest, download the tarball into build/cache/community-apps/dl
#      and check its sha256 (cached across runs; re-verified every run);
#   2. run the app's own install.sh --skip-apt (patched apps: --from-source
#      on a patched scratch copy) with a curl shim that serves the
#      verified tarball, so install.sh's own prebuilt_fetch re-checks the same
#      bytes and installs the desktop file, icons, i3 rules and plugins from the
#      pinned tree;
#   3. fail if any install.sh fell back to a source build;
#   4. ldd every staged ELF (no unresolved libraries on this host) and load each
#      Qt app's QML offscreen.
#
#   build-community-apps.sh [omaxian-src]
#   COMMUNITY_APPS_SKIP="omacut plain" build-community-apps.sh   # opt out
#
# Run on a Debian trixie / Devuan excalibur host (Qt 6.8): install.sh checks
# libqt6core6t64 >= the manifest's qt=. Does NOT install community-plugins.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
KEY_ONLY=0; [ "${1:-}" = --key ] && { KEY_ONLY=1; shift; }
SRC=$(realpath "${1:-${OMX:-$BUILDDIR/src/omaxian}}")
# Cache key: Omaxian commit (pins every manifest) + skip list + this builder
# + our compat patches.
ca_key() {
	{ git -C "$SRC" rev-parse HEAD 2>/dev/null || cat "$SRC/version"
	  echo "${COMMUNITY_APPS_SKIP:-}"
	  cat "$0" "$TOPDIR"/patches/community-apps/*/*.patch 2>/dev/null; } | sha256sum | cut -c1-16
}
if [ "$KEY_ONLY" = 1 ]; then ca_key; exit 0; fi
APPS="$SRC/community-apps"
OUT="$BUILDDIR/cache/community-apps/home"
CACHE="$BUILDDIR/cache/community-apps"
DL="$CACHE/dl"

die() { echo "error: $*" >&2; exit 1; }
need_dir() { [ -d "$1" ] || die "missing $1 (need Omaxian v1.2.0+ community-apps)"; }

need_dir "$APPS"
[ -f "$APPS/lib/prebuilt.sh" ] || die "$APPS/lib/prebuilt.sh missing (need Omaxian v1.2.0+ pre-built pins)"
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
[ "$(uname -m)" = x86_64 ] || die "community-apps: pinned binaries are x86_64 only (host $(uname -m))"

patched() { compgen -G "$TOPDIR/patches/community-apps/$1/*.patch" >/dev/null; }

# --- 1. fetch + verify every pinned tarball ---
mget() { awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$1"; }
mkdir -p "$DL" "$CACHE/shim"
: > "$CACHE/shim/urls"
for a in "${APPS_LIST[@]}"; do
	m="$APPS/$a/.omaxian-prebuilt"
	[ -f "$m" ] || die "community-apps: $a has no pinned pre-built binary ($m); the OS build does not compile apps"
	url=$(mget "$m" url); sha=$(mget "$m" sha256); arch=$(mget "$m" arch)
	case $url in https://*) ;; *) die "$m: url= must be https" ;; esac
	[[ $sha =~ ^[0-9a-f]{64}$ ]] || die "$m: bad sha256="
	[ "${arch:-x86_64}" = x86_64 ] || die "$m: arch=$arch, need x86_64"
	f="$DL/$a--$(basename "$url")"
	if [ ! -f "$f" ] || ! echo "$sha  $f" | sha256sum -c --status; then
		msg "community-apps: download $a ($url)"
		curl -fsSL --proto '=https' --tlsv1.2 --retry 2 -o "$f.part" "$url"
		mv "$f.part" "$f"
	fi
	echo "$sha  $f" | sha256sum -c --status || die "community-apps: $a: sha256 mismatch for $url"
	printf '%s\t%s\n' "$url" "$f" >> "$CACHE/shim/urls"
	msg "community-apps: $a pinned binary ok ($(mget "$m" tree | cut -c1-7), sha256 ${sha:0:12}…)"
done
# curl shim: install.sh's prebuilt_fetch downloads with `curl … -o FILE URL`;
# serve the verified cached tarball for pinned URLs, refuse anything else
# (no network surprises, no rustup/cargo/apt fallbacks from inside install.sh).
cat > "$CACHE/shim/curl" <<SHIM
#!/bin/bash
out=""; url=""
while [ \$# -gt 0 ]; do
	case \$1 in -o) out=\$2; shift ;; https://*|http://*) url=\$1 ;; esac
	shift
done
f=\$(awk -F'\t' -v u="\$url" '\$1 == u { print \$2; exit }' "$CACHE/shim/urls")
[ -n "\$f" ] && [ -n "\$out" ] || { echo "community-apps curl shim: refusing \$url" >&2; exit 22; }
exec cp "\$f" "\$out"
SHIM
chmod 755 "$CACHE/shim/curl"

# --- 2. install each app from its pinned binary ---
rm -rf "$OUT"
mkdir -p "$OUT/.local" "$OUT/.config/i3/config.d"
# Patched source build (Qt 6.8 compat). install.sh builds in-tree and sources
# ../lib/prebuilt.sh, so build from a scratch copy of <app>/ next to lib/.
build_patched() {
	local name=$1 dir pf
	command -v qmake6 >/dev/null || die "qmake6 required to build patched $name (Qt 6.8 dev packages)"
	rm -rf "$CACHE/src"
	mkdir -p "$CACHE/src"
	cp -a "$APPS/lib" "$CACHE/src/lib"
	cp -a "$APPS/$name" "$CACHE/src/$name"
	dir="$CACHE/src/$name"
	rm -rf "$dir/build"
	# Build only the app target: upstream test targets use Qt >= 6.9 APIs.
	if [ -f "$dir/bin/build" ]; then
		sed -i -E 's|^(\s*cmake --build "\$BUILD_DIR" -j"\$JOBS")\s*$|\1 --target '"$name"'|' "$dir/bin/build"
	fi
	for pf in "$TOPDIR/patches/community-apps/$name"/*.patch; do
		msg "community-apps: $name: patch $(basename "$pf")"
		patch -d "$dir" -p1 --forward --batch < "$pf" >/dev/null \
			|| die "community-apps: $(basename "$pf") no longer applies to $name (upstreamed? drop it)"
	done
	PATCHED_DIR=$dir
}

BUILT=()
for a in "${APPS_LIST[@]}"; do
	log="$CACHE/${a}-install.log"
	if patched "$a"; then
		msg "community-apps: $a (source build + Qt 6.8 compat patches)"
		build_patched "$a"; dir=$PATCHED_DIR; args=(--skip-apt --from-source)
	else
		msg "community-apps: $a (pre-built)"
		dir="$APPS/$a"; args=(--skip-apt)
	fi
	# install.sh refuses root and uses $HOME; --skip-apt: runtime deps come
	# from 55-community-apps.list / omaxian-session Depends.
	( cd "$dir" && env -i PATH="$CACHE/shim:/usr/bin:/bin" HOME="$OUT" USER="${USER:-omaxian}" \
		LANG=C.UTF-8 TMPDIR="${TMPDIR:-/tmp}" bash ./install.sh "${args[@]}" ) > "$log" 2>&1 \
		|| { cat "$log"; die "$a install.sh failed"; }
	# --- 3. an unpatched app must use its pin; a source build means it did not ---
	if ! patched "$a" && { ! grep -q '^>> sha256 ok' "$log" || grep -qiE 'building from source|cmake --build|cargo build|>> bin/build' "$log"; }; then
		cat "$log"; die "community-apps: $a did not install its pinned pre-built binary"
	fi
	BUILT+=("$a")
done
# build trees are large; the stage is what we keep
[ "${COMMUNITY_APPS_KEEP_SRC:-0}" = 1 ] || rm -rf "$CACHE/src"

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

# --- 4a. every staged ELF links on this host ---
while IFS= read -r -d '' f; do
	head -c4 "$f" | grep -q 'ELF' || continue
	if ldd "$f" 2>&1 | grep -q 'not found'; then
		ldd "$f" | grep 'not found'; die "community-apps: ${f#$OUT/} has unresolved libraries"
	fi
done < <(find "$OUT/.local/bin" "$OUT/.local/libexec" -type f -perm -u+x -print0 2>/dev/null)
msg "community-apps: all binaries resolve their libraries (ldd)"

# --- 4b. QML smoke test (offscreen): catch QML that fails on Qt 6.8 ---
if [ "${COMMUNITY_APPS_SMOKE:-1}" = 1 ]; then
	SM=$(mktemp -d /tmp/omaxian-ca-smoke.XXXXXX)
	mkdir -m700 "$SM/run"
	for a in "${BUILT[@]}"; do
		case $a in disktree|omarchy-meeting-recorder) continue ;; esac
		arg=(); [ "$a" = signed ] && arg=(open)
		env -i PATH="/usr/bin:/bin" HOME="$SM" XDG_RUNTIME_DIR="$SM/run" LANG=C.UTF-8 \
			QT_QPA_PLATFORM=offscreen timeout 8 "$OUT/.local/bin/$a" "${arg[@]}" \
			> "$CACHE/$a-smoke.log" 2>&1 || true
		if grep -E 'non-existent property|failed to load component|is not a type|module "[^"]+" is not installed|Type [A-Za-z]+ unavailable|error while loading shared libraries|undefined symbol' \
			"$CACHE/$a-smoke.log"; then
			rm -rf "$SM"; die "community-apps: $a does not load on this Qt (see $CACHE/$a-smoke.log)"
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
ls -la "$OUT/.local/bin" || true
