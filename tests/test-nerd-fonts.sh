#!/bin/bash
# test-nerd-fonts.sh: omaxian-fonts-nerd + fetch-nerd-fonts.sh
#  1. fetch script accepts the pinned archive and rejects a wrong pin
#  2. changelog version == NERD_FONTS_VERSION; omaxian-session Depends on it
#  3. built deb: TTFs at the system path, OFL, fontconfig conf + conf.d link,
#     postinst runs fc-cache
#  4. fontconfig: "monospace" resolves to JetBrainsMono Nerd Font
# Needs the cached archive (or network) and out/debs/omaxian-fonts-nerd_*.deb.
set -uo pipefail
TOP=$(cd "$(dirname "$0")/.." && pwd); . "$TOP/config/build.conf"
fail=0; ok() { echo "ok   $*"; }; bad() { echo "FAIL $*"; fail=1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# 1
if bash "$TOP/scripts/fetch-nerd-fonts.sh" "$T/good" >"$T/log" 2>&1 \
   && [ "$(ls "$T/good/ttf" | wc -l)" -eq $((16 * $(wc -w <<<"$NERD_FONTS_JBM_VARIANTS"))) ] \
   && [ -s "$T/good/OFL.txt" ]; then ok "fetch: pinned sha256 accepted, $(ls "$T/good/ttf" | wc -l) TTFs"
else bad "fetch with pinned sha256"; cat "$T/log"; fi
# wrong pin must be rejected without deleting the shared cache: use a copy
mkdir -p "$T/b/dl/nerd-fonts-$NERD_FONTS_VERSION"
cp "$BUILDDIR/dl/nerd-fonts-$NERD_FONTS_VERSION/JetBrainsMono.tar.xz" "$T/b/dl/nerd-fonts-$NERD_FONTS_VERSION/" 2>/dev/null
if BUILDDIR=$T/b NERD_FONTS_JBM_SHA256=$(printf '0%.0s' {1..64}) bash "$TOP/scripts/fetch-nerd-fonts.sh" "$T/bad" >"$T/log" 2>&1; then
	bad "fetch accepted a wrong sha256"
else grep -q "sha256 mismatch" "$T/log" && ok "fetch: wrong sha256 rejected" || { bad "fetch failed for another reason"; cat "$T/log"; }; fi
if BUILDDIR=$T/b NERD_FONTS_JBM_VARIANTS="Bogus" bash "$TOP/scripts/fetch-nerd-fonts.sh" "$T/bad2" >"$T/log" 2>&1; then
	bad "unknown variant accepted"; else ok "fetch: unknown variant rejected"; fi

# 2
v=$(sed -n '1s/.*(\([^-)]*\).*/\1/p' "$TOP/packages/omaxian-fonts-nerd/debian/changelog")
[ "$v" = "$NERD_FONTS_VERSION" ] && ok "changelog $v == NERD_FONTS_VERSION" || bad "changelog $v != $NERD_FONTS_VERSION"
awk '/^Package: omaxian-session$/{p=1} p&&/^Depends:/{d=1} d&&/^(Recommends|Suggests|Description):/{exit} d' "$TOP/packages/omaxian-session/debian/control" | grep -qE '(^|[ ,])omaxian-fonts-nerd(,|$)' \
	&& ok "omaxian-session Depends: omaxian-fonts-nerd" || bad "omaxian-session does not depend on omaxian-fonts-nerd"
grep -qx omaxian-fonts-nerd "$TOP/config/package-lists/50-omaxian.list" && ok "in 50-omaxian.list" || bad "not in 50-omaxian.list"

# 3
deb=$(ls "$OUTDIR"/debs/omaxian-fonts-nerd_"$NERD_FONTS_VERSION"-*_all.deb 2>/dev/null | tail -1)
if [ -n "$deb" ]; then
	dpkg-deb -x "$deb" "$T/root"; dpkg-deb -e "$deb" "$T/ctl"
	n=$(ls "$T/root/usr/share/fonts/truetype/jetbrains-mono-nerd/"*.ttf 2>/dev/null | wc -l)
	[ "$n" -ge 16 ] && ok "deb: $n TTFs in /usr/share/fonts/truetype/jetbrains-mono-nerd" || bad "deb: $n TTFs"
	cmp -s "$T/root/usr/share/fonts/truetype/jetbrains-mono-nerd/JetBrainsMonoNerdFont-Regular.ttf" "$T/good/ttf/JetBrainsMonoNerdFont-Regular.ttf" \
		&& ok "deb: TTF byte-identical to verified release" || bad "deb: TTF differs from release"
	[ -s "$T/root/usr/share/doc/omaxian-fonts-nerd/OFL.txt" ] && grep -q "SIL Open Font License" "$T/root/usr/share/doc/omaxian-fonts-nerd/OFL.txt" \
		&& ok "deb: OFL.txt" || bad "deb: OFL.txt missing"
	grep -q "^License: OFL-1.1" "$T/root/usr/share/doc/omaxian-fonts-nerd/copyright" && ok "deb: copyright OFL-1.1" || bad "deb: copyright"
	[ "$(readlink "$T/root/etc/fonts/conf.d/56-omaxian-monospace.conf")" = /usr/share/fontconfig/conf.avail/56-omaxian-monospace.conf ] \
		&& ok "deb: conf.d link" || bad "deb: conf.d link"
	grep -q 'fc-cache -s -f /usr/share/fonts/truetype/jetbrains-mono-nerd' "$T/ctl/postinst" && ok "deb: postinst fc-cache" || bad "deb: postinst fc-cache"
	sh -n "$T/ctl/postinst" && sh -n "$T/ctl/postrm" && ok "deb: maintainer scripts parse" || bad "deb: script syntax"
	# 4
	if command -v fc-match >/dev/null; then
		cat > "$T/fonts.conf" <<XML
<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig><dir>$T/root/usr/share/fonts</dir><dir>/usr/share/fonts</dir><cachedir>$T/cache</cachedir>
<include>$T/root/usr/share/fontconfig/conf.avail/56-omaxian-monospace.conf</include>
<include ignore_missing="yes">/etc/fonts/conf.d/60-latin.conf</include></fontconfig>
XML
		m=$(FONTCONFIG_FILE=$T/fonts.conf fc-match -f '%{family}' monospace)
		[[ $m == "JetBrainsMono Nerd Font Mono"* ]] && ok "fc-match monospace -> $m" || bad "fc-match monospace -> $m"
		m=$(FONTCONFIG_FILE=$T/fonts.conf fc-match -f '%{family}' "JetBrainsMono Nerd Font")
		[[ $m == "JetBrainsMono Nerd Font"* ]] && ok "fc-match 'JetBrainsMono Nerd Font' -> $m" || bad "fc-match family -> $m"
	else echo "skip fc-match (fontconfig not installed)"; fi
else bad "no out/debs/omaxian-fonts-nerd deb (run scripts/build-packages.sh omaxian-fonts-nerd)"; fi
exit $fail
