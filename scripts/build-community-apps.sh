#!/bin/bash
# Stage ALL Omaxian community-apps (every community-apps/<id>/ that ships an
# install.sh) into build/cache/community-apps/home (a partial home: .local/…
# and .config/i3/config.d/…).
#
# Every app installs its sha256-pinned .omaxian-prebuilt binary, including
# flowtunes, fantasi and omarchy-local-ai (shell v1.2.4 CI). Compilers on
# install.sh's PATH fail the build, so a missing or stale pin cannot fall
# back to a source build.
#
# The stage runs on Debian trixie / Devuan excalibur (Qt 6.8). On any other
# host it re-enters a trixie chroot (scripts/ensure-build-chroot.sh) so ldd
# and the offscreen QML check see the same Qt the binaries were built for.
#
#   build-community-apps.sh [omaxian-src]
#   COMMUNITY_APPS_SKIP="omacut plain" build-community-apps.sh
#   COMMUNITY_APPS_STALE_OK="monologue" build-community-apps.sh
set -euo pipefail
. "$(dirname "$0")/lib.sh"
KEY_ONLY=0; [ "${1:-}" = --key ] && { KEY_ONLY=1; shift; }
SRC=$(realpath "${1:-${OMX:-$BUILDDIR/src/omaxian}}")
# Cache key: Omaxian commit + skip list + this builder.
ca_key() {
	{ git -C "$SRC" rev-parse HEAD 2>/dev/null || cat "$SRC/version"
	  echo "${COMMUNITY_APPS_SKIP:-}|${COMMUNITY_APPS_STALE_OK:-}"
	  cat "$0"; } | sha256sum | cut -c1-16
}
if [ "$KEY_ONLY" = 1 ]; then ca_key; exit 0; fi

# Pinned binaries need libqt6core6t64 (Qt 6.8).
if [ "${OMAXIAN_CA_HOST:-}" != 1 ] && ! dpkg-query -W -f '${Status}' libqt6core6t64 2>/dev/null | grep -q 'install ok installed'; then
	[ "$(id -u)" -eq 0 ] || exec sudo bash "$0" "$@"
	bash "$TOPDIR/scripts/ensure-build-chroot.sh" "$SRC"
	CHROOT=${OMAXIAN_TRIXIE_CHROOT:-/var/lib/omaxian-trixie}
	mkdir -p "$CHROOT/workspace" "$CHROOT/tmp"
	mountpoint -q "$CHROOT/proc" || mount -t proc proc "$CHROOT/proc"
	mountpoint -q "$CHROOT/dev" || mount --bind /dev "$CHROOT/dev"
	mountpoint -q "$CHROOT/workspace" || mount --bind "$TOPDIR" "$CHROOT/workspace"
	cp /etc/resolv.conf "$CHROOT/etc/resolv.conf"
	exec chroot "$CHROOT" /usr/bin/env -i \
		HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
		OMAXIAN_CA_HOST=1 \
		SUDO_UID="${SUDO_UID:-}" SUDO_GID="${SUDO_GID:-}" \
		COMMUNITY_APPS_SKIP="${COMMUNITY_APPS_SKIP:-}" \
		COMMUNITY_APPS_STALE_OK="${COMMUNITY_APPS_STALE_OK:-}" \
		COMMUNITY_APPS_SMOKE="${COMMUNITY_APPS_SMOKE:-1}" \
		bash /workspace/scripts/build-community-apps.sh /workspace/build/src/omaxian
fi

APPS="$SRC/community-apps"
OUT="$BUILDDIR/cache/community-apps/home"
CACHE="$BUILDDIR/cache/community-apps"
DL="$CACHE/dl"

die() { echo "error: $*" >&2; exit 1; }
need_dir() { [ -d "$1" ] || die "missing $1 (need Omaxian v1.2.0+ community-apps)"; }

need_dir "$APPS"
[ -f "$APPS/lib/prebuilt.sh" ] || die "$APPS/lib/prebuilt.sh missing (need Omaxian v1.2.0+ pre-built pins)"
mapfile -t ALL_APPS < <(find "$APPS" -mindepth 2 -maxdepth 2 -name install.sh -printf '%h\n' \
	| xargs -r -n1 basename | sort)
APPS_LIST=()
for a in "${ALL_APPS[@]}"; do
	case " ${COMMUNITY_APPS_SKIP:-} " in *" $a "*) warn "community-apps: skipping $a (COMMUNITY_APPS_SKIP)"; continue ;; esac
	APPS_LIST+=("$a")
done
for a in disktree folio monologue omarchy-meeting-recorder signed; do
	need_dir "$APPS/$a"
done
msg "community-apps: ${APPS_LIST[*]}"
[ "$(uname -m)" = x86_64 ] || die "community-apps: pinned binaries are x86_64 only (host $(uname -m))"

if [ "$(id -u)" -eq 0 ]; then
	id builder >/dev/null 2>&1 || useradd --create-home --shell /bin/bash builder
	RUN_AS=(su -s /bin/bash builder -c)
else
	RUN_AS=()
fi
run_user() { # $1 = shell command
	if [ ${#RUN_AS[@]} -gt 0 ]; then "${RUN_AS[@]}" "$1"; else bash -c "$1"; fi
}

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

# --- 2. install each app ---
rm -rf "$OUT"
mkdir -p "$OUT/.local" "$OUT/.config/i3/config.d"
# Compiler blockers: a fallback to a source build must fail fast, not quietly
# compile with whatever the build host has.
for t in cmake qmake6 qmake cargo rustup cc gcc g++ c++; do
	printf '#!/bin/sh\necho "community-apps: %s blocked (pinned pre-built binaries only)" >&2\nexit 97\n' "$t" \
		> "$CACHE/shim/$t"
	chmod 755 "$CACHE/shim/$t"
done

stale_ok() { case " ${COMMUNITY_APPS_STALE_OK:-} " in *" $1 "*) return 0 ;; esac; return 1; }
BUILT=(); STALE_DIR=""
trap '[ -z "$STALE_DIR" ] || rm -rf "$STALE_DIR"' EXIT
for a in "${APPS_LIST[@]}"; do
	log="$CACHE/${a}-install.log"
	dir="$APPS/$a"
	if stale_ok "$a"; then
		warn "community-apps: $a: installing its pinned binary even if its sources changed since (COMMUNITY_APPS_STALE_OK)"
		[ -n "$STALE_DIR" ] || STALE_DIR=$(mktemp -d /tmp/omaxian-ca-stale.XXXXXX)
		rm -rf "${STALE_DIR:?}/$a"; mkdir -p "$STALE_DIR"
		[ -d "$STALE_DIR/lib" ] || cp -a "$APPS/lib" "$STALE_DIR/lib"
		cp -a "$APPS/$a" "$STALE_DIR/$a"
		dir="$STALE_DIR/$a"
	fi
	msg "community-apps: $a (pre-built)"
	path="$CACHE/shim:/usr/bin:/bin"
	who=${USER:-omaxian}
	if [ "$(id -u)" -eq 0 ]; then
		who=builder
		chown -R builder:builder "$OUT"
	fi
	run_user "cd $(printf %q "$dir") && env -i PATH=$(printf %q "$path") HOME=$(printf %q "$OUT") USER=$who LANG=C.UTF-8 TMPDIR=${TMPDIR:-/tmp} bash ./install.sh --skip-apt" \
		> "$log" 2>&1 \
		|| { cat "$log"; die "$a install.sh failed (a source-build fallback fails here by design)"; }
	if ! grep -q '^>> sha256 ok' "$log" || grep -qiE 'building from source|cmake --build|cargo build|>> bin/build|blocked \(pinned' "$log"; then
		cat "$log"; die "community-apps: $a did not install its pinned pre-built binary"
	fi
	BUILT+=("$a")
done
[ -z "$STALE_DIR" ] || { rm -rf "$STALE_DIR"; STALE_DIR=""; }
rm -rf "$CACHE/src"

# Desktop files, dbus services and anything else install.sh wrote must not
# embed the staging home. ~/.local/bin is on PATH, so a bare command is enough.
while read -r f; do
	[ -n "$f" ] || continue
	sed -i "s|$OUT/.local/bin/||g" "$f"
done < <(grep -rIl -F "$OUT/.local/bin/" "$OUT" 2>/dev/null || true)
if grep -rIl --exclude-dir=themes "$OUT" "$OUT" 2>/dev/null | head -5 | grep -q .; then
	grep -rIl --exclude-dir=themes "$OUT" "$OUT" | head
	die "community-apps stage still contains staging path $OUT"
fi
chmod -R a+rX "$OUT" "$CACHE" 2>/dev/null || true
if [ -n "${SUDO_UID:-}" ]; then
	chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$OUT" "$CACHE" 2>/dev/null || true
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

is_qml() { jq -e '.apt // [] | index("qml6-module-qtquick")' "$APPS/$1/omaxian.deps.json" >/dev/null 2>&1; }

# --- 4b. QML smoke test (offscreen): catch QML that fails on Qt 6.8 ---
if [ "${COMMUNITY_APPS_SMOKE:-1}" = 1 ]; then
	SM=$(mktemp -d /tmp/omaxian-ca-smoke.XXXXXX)
	mkdir -m700 "$SM/run"
	for a in "${BUILT[@]}"; do
		is_qml "$a" || continue
		mapfile -t arg < <(jq -r '.start_args // [] | .[]' "$APPS/$a/omaxian.deps.json" 2>/dev/null || true)
		env -i PATH="/usr/bin:/bin" HOME="$SM" XDG_RUNTIME_DIR="$SM/run" LANG=C.UTF-8 \
			QT_QPA_PLATFORM=offscreen timeout 20 "$OUT/.local/bin/$a" "${arg[@]}" \
			> "$CACHE/$a-smoke.log" 2>&1 || true
		if grep -E 'non-existent property|failed to load component|is not a type|module "[^"]+" is not installed|Type [A-Za-z]+ unavailable|error while loading shared libraries|undefined symbol' \
			"$CACHE/$a-smoke.log"; then
			rm -rf "$SM"; die "community-apps: $a does not load on this Qt (see $CACHE/$a-smoke.log)"
		fi
		msg "community-apps: $a QML loads (offscreen)"
	done
	rm -rf "$SM"
fi
for a in "${BUILT[@]}"; do
	[ -e "$OUT/.local/bin/$a" ] || die "community-apps: $a produced no ~/.local/bin/$a"
	if find "$APPS/$a" -name '*.desktop' -print -quit | grep -q .; then
		compgen -G "$OUT/.local/share/applications/*${a%%-*}*.desktop" >/dev/null \
			|| die "community-apps: $a installed no desktop entry"
	fi
done
for a in "${BUILT[@]}"; do
	if stale_ok "$a"; then printf '%s\tstale-pin\n' "$a"; else printf '%s\n' "$a"; fi
done > "$CACHE/installed.txt"
ca_key > "$CACHE/stamp"
ls -la "$OUT/.local/bin" || true
