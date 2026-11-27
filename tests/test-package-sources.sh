#!/bin/bash
# Hermetic tests for tools/package-sources.sh: origins from apt lists when
# present; inferred (and honestly labelled) from a packages file otherwise;
# pin hashes come from config/build.conf, never invented.
set -u
cd "$(dirname "$0")/.." || exit
pass=0; fail=0
ok() { echo "ok   $*"; pass=$((pass+1)); }
bad() { echo "FAIL $*"; fail=$((fail+1)); }

S=tools/package-sources.sh
bash -n "$S" && ok "bash -n package-sources.sh" || bad "bash -n package-sources.sh"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# tiny packages listing (tab-separated, like dpkg-query -W)
printf '%s\n' \
	'omaxian-base	0.2.1' \
	'omaxian-session	1.2.2-1' \
	'quickshell	0.3.0-1~bpo13+1' \
	'linux-image-amd64	7.2.12-1~bpo13+1' \
	'xserver-xlibre-core	2:25.2.2-1' \
	'brave-browser	1.99.57' \
	'librewolf	160.0-1' \
	'bash	5.2.37-1+b3' \
	> "$T/pkgs"

OUTDIR=$T/out BUILDDIR=$T/build TOPDIR=$PWD \
	bash "$S" --packages "$T/pkgs" --flavor base --version 0.2.1 --out "$T/out.md"
[ -s "$T/out.md" ] && ok "wrote markdown from a packages file" || bad "no markdown written"

# inferred origins (no apt lists)
grep -q 'apt.omaxian.org' "$T/out.md" && grep -q 'omaxian-base' "$T/out.md" \
	&& ok "omaxian-base under apt.omaxian.org" || bad "omaxian-base origin missing"
grep -q 'excalibur-backports' "$T/out.md" && grep -q 'quickshell' "$T/out.md" \
	&& ok "quickshell inferred as backports from ~bpo13+" || bad "quickshell backports missing"
grep -q 'XLibre' "$T/out.md" && grep -q 'xserver-xlibre-core' "$T/out.md" \
	&& ok "xserver-xlibre-core under XLibre" || bad "XLibre origin missing"
grep -q 'Brave apt' "$T/out.md" && ok "brave-browser under Brave extrepo" || bad "Brave origin missing"
grep -q 'LibreWolf apt' "$T/out.md" && ok "librewolf under LibreWolf extrepo" || bad "LibreWolf origin missing"
grep -q 'not distinguished' "$T/out.md" && grep -q 'bash' "$T/out.md" \
	&& ok "plain Devuan package is not given a fake suite" || bad "bash origin wording off"

# hashes only from config
. config/build.conf
grep -Fq "$NERD_FONTS_JBM_SHA256" "$T/out.md" && ok "Nerd Fonts sha256 from build.conf" || bad "nerd fonts hash missing"
grep -Fq "$YDOTOOL_SRC_SHA256" "$T/out.md" && ok "ydotool sha256 from build.conf" || bad "ydotool hash missing"
grep -Fq "$VOXTYPE_DEB_SHA256" "$T/out.md" && ok "voxtype sha256 from build.conf" || bad "voxtype hash missing"
# must not invent a Strata sha256 when none was recorded
if grep -qiE 'strata.*sha256 `[0-9a-f]{64}`' "$T/out.md"; then
	bad "invented a Strata sha256"
else
	ok "no invented Strata sha256"
fi
grep -q 'not stored in this repo' "$T/out.md" && ok "Strata sha256 is described as manifest-verified" || bad "Strata wording missing"

# community pins when a pin dir is provided (real fields, not invented)
mkdir -p "$T/apps/folio"
cat > "$T/apps/folio/.omaxian-prebuilt" <<'PIN'
url=https://example.invalid/folio.tar.gz
sha256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
tree=deadbeef
bin=folio-x/folio
arch=x86_64
PIN
OUTDIR=$T/out BUILDDIR=$T/build TOPDIR=$PWD \
	bash "$S" --packages "$T/pkgs" --flavor base --version 0.2.1 \
		--community-apps "$T/apps" --out "$T/out2.md"
grep -Fq '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' "$T/out2.md" \
	&& grep -q 'folio' "$T/out2.md" \
	&& ok "community-app pin table uses the provided sha256" \
	|| bad "community pin not in markdown"

# apt-lists path: exact suite from the list file name
mkdir -p "$T/root/var/lib/dpkg" "$T/lists"
printf 'Package: bash\nStatus: install ok installed\nVersion: 5.2.37-1+b3\n\n' > "$T/root/var/lib/dpkg/status"
printf 'Package: bash\nVersion: 5.2.37-1+b3\n\n' > \
	"$T/lists/packages.devuan.org_merged_dists_excalibur-security_main_binary-amd64_Packages"
# also a packages file matching dpkg-query
printf 'bash\t5.2.37-1+b3\n' > "$T/from-root.packages"
# We need dpkg-query --admindir to list bash. The status above is enough.
OUTDIR=$T/out BUILDDIR=$T/build TOPDIR=$PWD \
	bash "$S" --rootfs "$T/root" --lists "$T/lists" --flavor base --version 0.2.1 --out "$T/out3.md"
grep -q 'excalibur-security' "$T/out3.md" \
	&& ok "apt list file name yields excalibur-security" \
	|| { bad "security suite not used: $(grep -A2 '## ' "$T/out3.md" | head)"; }

# count
grep -q 'Installed packages listed: \*\*8\*\*' "$T/out.md" \
	&& ok "package count is 8" || bad "count line: $(grep -F 'Installed packages' "$T/out.md")"

echo "== $pass passed, $fail failed"
[ "$fail" = 0 ]
