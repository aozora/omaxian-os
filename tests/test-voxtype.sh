#!/bin/bash
# VoxType (full-ISO-only 7th optional group): fetch verification, netinstall
# groups (base 6 / full 7), offline-only packages never pending, CPU-adaptive
# wrapper, i3 seeding, toggle logic. No network (uses build/dl cache).
set -u
TOPDIR=$(cd "$(dirname "$0")/.." && pwd); cd "$TOPDIR"
. config/build.conf
pass=0 fail=0; ok() { echo "ok   $*"; pass=$((pass+1)); }; bad() { echo "FAIL $*"; fail=$((fail+1)); }
export PYTHONDONTWRITEBYTECODE=1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
V=$VOXTYPE_VERSION DEB="voxtype_${VOXTYPE_VERSION}-${VOXTYPE_DEB_REV}_amd64.deb" REAL="$BUILDDIR/dl/voxtype-$VOXTYPE_VERSION"

# --- fetch verification (on symlinks to the cache: a failing check deletes only the link)
if [ -s "$REAL/$DEB" ]; then
	mk() { rm -rf "$T/b"; mkdir -p "$T/b/dl/voxtype-$V"; for f in "$DEB" "$DEB.asc" SHA256SUMS.txt SHA256SUMS.txt.asc; do ln -s "$REAL/$f" "$T/b/dl/voxtype-$V/$f"; done; }
	F() { BUILDDIR=$T/b PAYLOADDIR=$T/nopayload bash scripts/fetch-voxtype.sh "$@" >"$T/f.log" 2>&1; }
	mk; F "$T/out" && [ -s "$T/out/$DEB" ] && ok "fetch: pinned sha256 + signature + signed sums OK" || { bad "fetch good"; cat "$T/f.log"; }
	mk; VOXTYPE_DEB_SHA256=$(printf '0%.0s' {1..64}) F && bad "fetch accepted a wrong sha256" || { grep -q "sha256 mismatch" "$T/f.log" && [ ! -e "$T/b/dl/voxtype-$V/$DEB" ] && ok "fetch: wrong sha256 rejected, file dropped" || bad "fetch sha msg"; }
	mk; rm "$T/b/dl/voxtype-$V/$DEB.asc"; ln -s "$REAL/SHA256SUMS.txt.asc" "$T/b/dl/voxtype-$V/$DEB.asc"
	F && bad "fetch accepted a bad .deb signature" || { grep -q "bad or missing signature" "$T/f.log" && ok "fetch: bad .deb signature rejected" || bad "fetch sig msg"; }
	mk; rm "$T/b/dl/voxtype-$V/SHA256SUMS.txt"; sed 's/^\(.\)/f/' "$REAL/SHA256SUMS.txt" > "$T/b/dl/voxtype-$V/SHA256SUMS.txt"
	F && bad "fetch accepted tampered SHA256SUMS.txt" || { grep -q "SHA256SUMS.txt: bad signature" "$T/f.log" && ok "fetch: tampered SHA256SUMS.txt rejected" || bad "sums msg"; }
	mk; VOXTYPE_SIGNING_FPR=0000000000000000000000000000000000000000 F && bad "fetch accepted another signer" || ok "fetch: signature by a different key rejected"
else
	echo "skip fetch tests: $REAL/$DEB not cached (run scripts/fetch-voxtype.sh)"
fi

# --- netinstall: base 6 groups (all on), full 7 (VoxType off)
bash scripts/gen-netinstall.sh config/optional-groups.list "$T/base.conf"
bash scripts/gen-netinstall.sh config/optional-groups.list "$T/full.conf" config/optional-groups-full.list
nb=$(grep -c '^    - name:' "$T/base.conf"); nf=$(grep -c '^    - name:' "$T/full.conf")
[ "$nb" = 6 ] && ! grep -q voxtype "$T/base.conf" && ok "base netinstall: 6 groups, no VoxType" || bad "base groups=$nb"
[ "$nf" = 7 ] && ok "full netinstall: 7 groups" || bad "full groups=$nf"
sel=$(awk '/^    - name:/{n=$0} /selected:/{print n"|"$2}' "$T/full.conf")
[ "$(grep -c '|true' <<<"$sel")" = 6 ] && grep -q 'VoxType.*|false' <<<"$sel" && ok "full: 6 groups preselected, VoxType unselected" || { bad "selected"; echo "$sel"; }
grep -q 'netinstall.conf" "$TOPDIR/config/optional-groups.list"' scripts/build-packages.sh ||
	grep -q 'gen-netinstall.sh" "$TOPDIR/config/optional-groups.list" "$1/files' scripts/build-packages.sh && ok "package netinstall.conf (base) built from optional-groups.list only" || bad "build-packages"

# --- omaxianoptional: offline-only packages are never pending
M=packages/omaxian-calamares-settings/files/usr/lib/x86_64-linux-gnu/calamares/modules/omaxianoptional
mkdir -p "$T/py/libcalamares" "$T/root"
cat > "$T/py/libcalamares/__init__.py" <<'P'
import types
_g = {}
globalstorage = types.SimpleNamespace(value=lambda k: _g.get(k))
log = []
utils = types.SimpleNamespace(debug=lambda m: log.append(m), warning=lambda m: log.append("W:" + m))
P
cat > "$T/run.py" <<P
import sys; sys.path[:0] = ["$T/py", "$M"]
import libcalamares, main
libcalamares._g.update(rootMountPoint="$T/root", packageOperations=[{"install": sys.argv[2].split()}])
inst = set(sys.argv[3].split())
main._installed = lambda root, p: p in inst
main.OFFLINE_ONLY = sys.argv[1]
print(main.run())
print("\n".join(libcalamares.log))
P
printf 'voxtype\nomaxian-voxtype\n' > "$T/only"
pend() { cat "$T/root/var/lib/omaxian/optional-pending.list" | tr '\n' ' '; }
python3 "$T/run.py" "$T/only" "krita voxtype omaxian-voxtype" "krita voxtype omaxian-voxtype" >/dev/null && [ -z "$(pend)" ] && ok "optional: all installed -> nothing pending" || bad "all installed: $(pend)"
o=$(python3 "$T/run.py" "$T/only" "krita voxtype omaxian-voxtype" "")
[ "$(pend)" = "krita " ] && grep -q "W:.*voxtype" <<<"$o" && ok "optional: voxtype not installed -> warned, not pending (krita pending)" || bad "offline-only pending: $(pend)"
python3 "$T/run.py" "$T/nonexistent" "krita voxtype" "" >/dev/null && [ "$(pend)" = "krita voxtype " ] && ok "optional: no offline-only list -> unchanged behaviour" || bad "no list: $(pend)"

# --- wrapper CPU selection
W=packages/omaxian-voxtype/files/usr/bin/voxtype; L="$T/lib"; mkdir -p "$L"
for b in avx512 avx2 baseline vulkan; do printf '#!/bin/sh\necho %s "$@"\n' $b > "$L/voxtype-$b"; chmod +x "$L/voxtype-$b"; done
cpu() { printf 'processor : 0\nflags\t\t: fpu sse2 %s\n' "$1" > "$T/cpu"; VOXTYPE_LIB=$L OMAXIAN_CPUINFO=$T/cpu sh "$W" --version; }
[ "$(cpu 'avx2 fma avx512f')" = "avx512 --version" ] && ok "wrapper: avx512f -> avx512" || bad "avx512"
[ "$(cpu 'avx2 fma')" = "avx2 --version" ] && ok "wrapper: avx2+fma -> avx2" || bad "avx2"
[ "$(cpu 'avx ssse3 sse4_1 sse4_2 popcnt cx16')" = "baseline --version" ] && ok "wrapper: no AVX2 -> baseline (upstream would SIGILL)" || bad "baseline"
[ "$(cpu 'avx2 ssse3 sse4_1 sse4_2 popcnt cx16')" = "baseline --version" ] && ok "wrapper: avx2 without fma -> baseline" || bad "avx2 nofma"
o=$(cpu 'sse3 cx16' 2>&1); rc=$?; [ $rc = 132 ] && case "$o" in *x86-64-v2*) true;; *) false;; esac && ok "wrapper: pre-v2 CPU (qemu64) -> clean error 132, no SIGILL" || bad "pre-v2: rc=$rc $o"
[ "$(VOXTYPE_GPU=1 VOXTYPE_LIB=$L sh "$W" x)" = "vulkan x" ] && ok "wrapper: VOXTYPE_GPU=1 -> vulkan" || bad "vulkan"
grep -q 'dpkg-divert --package omaxian-voxtype --add --rename' packages/omaxian-voxtype/debian/omaxian-voxtype.preinst &&
	grep -q 'listpackage /usr/bin/voxtype' packages/omaxian-voxtype/debian/omaxian-voxtype.postrm && ok "diversion: added in preinst, removed only if ours" || bad "diversion"

# --- i3 seeding: once, never re-created, no input group anywhere
H="$T/home"; mkdir -p "$H/.config/i3/config.d"
HOME=$H XDG_STATE_HOME= sh packages/omaxian-voxtype/files/usr/libexec/omaxian/voxtype-seed-i3
grep -q '^bindsym Mod4+Ctrl+v exec --no-startup-id /usr/bin/omaxian-voxtype-toggle' "$H/.config/i3/config.d/60-voxtype.conf" && ok "i3: Mod4+Ctrl+v seeded" || bad "seed"
rm "$H/.config/i3/config.d/60-voxtype.conf"; HOME=$H sh packages/omaxian-voxtype/files/usr/libexec/omaxian/voxtype-seed-i3
[ ! -e "$H/.config/i3/config.d/60-voxtype.conf" ] && ok "i3: deleted binding stays deleted" || bad "reseed"
! grep -rqE 'usermod|adduser|gpasswd|groupadd' packages/omaxian-voxtype && ok "no input-group changes in omaxian-voxtype" || bad "group change"

# --- toggle: no model -> setup terminal; model -> daemon started then toggle
B="$T/bin"; mkdir -p "$B"; S="$T/calls"
for c in notify-send kitty voxtype setsid; do printf '#!/bin/sh\necho %s "$*" >> %s\n' $c "$S" > "$B/$c"; done
printf '#!/bin/sh\n[ -e %s/running ]\n' "$T" > "$B/pgrep"
printf '#!/bin/sh\necho setsid "$*" >> %s; touch %s/running\n' "$S" "$T" > "$B/setsid"; chmod +x "$B"/*
TG=packages/omaxian-voxtype/files/usr/bin/omaxian-voxtype-toggle
: > "$S"; HOME=$H XDG_DATA_HOME= PATH="$B:$PATH" sh $TG
grep -q '^kitty .*voxtype setup model' "$S" && ! grep -q '^voxtype record' "$S" && ok "toggle: no model -> 'voxtype setup model' terminal" || { bad "nomodel"; cat "$S"; }
mkdir -p "$H/.local/share/voxtype/models"; touch "$H/.local/share/voxtype/models/ggml-base.en.bin"
: > "$S"; HOME=$H PATH="$B:$PATH" sh $TG
grep -q '^setsid -f voxtype -q daemon --clipboard' "$S" && tail -1 "$S" | grep -q '^voxtype record toggle' && ok "toggle: starts daemon (clipboard) then toggles" || { bad "start"; cat "$S"; }
: > "$S"; HOME=$H PATH="$B:$PATH" sh $TG
! grep -q setsid "$S" && grep -q '^voxtype record toggle' "$S" && ok "toggle: daemon running -> toggle only" || { bad "running"; cat "$S"; }
echo "--- $pass passed, $fail failed"; [ $fail = 0 ]
