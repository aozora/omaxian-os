#!/bin/bash
# test-xfpm-power-button.sh: omaxian-xfpm-defaults sets the user's
# xfce4-power-manager power-button-action=4 (shutdown) only when unset.
set -uo pipefail
TOP=$(cd "$(dirname "$0")/.." && pwd); S=$TOP/packages/omaxian-session/files
H=$S/usr/bin/omaxian-xfpm-defaults
fail=0; ok() { echo "ok   $*"; }; bad() { echo "FAIL $*"; fail=1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
C=xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml
val() { python3 - "$1" <<'P'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
v = [p.get("value") for t in r.findall("property") if t.get("name") == "xfce4-power-manager"
     for p in t.findall("property") if p.get("name") == "power-button-action"]
print(",".join(v) or "unset")
P
}
[ -x "$H" ] && ok "helper executable" || bad "helper not executable"
grep -q /usr/bin/omaxian-xfpm-defaults "$S/etc/X11/Xsession.d/36omaxian-xfpm" && ok "Xsession.d/36omaxian-xfpm calls it" || bad "Xsession.d hook"
# 1. fresh home -> file created with 4
HOME=$T/a XDG_CONFIG_HOME= python3 "$H"; [ "$(val "$T/a/.config/$C")" = 4 ] && ok "fresh home: created, value 4" || bad "fresh home"
# 2. existing file without the property (like the live 37omaxian-live one) -> added, others kept
mkdir -p "$(dirname "$T/b/.config/$C")"
cat > "$T/b/.config/$C" <<'X'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="dpms-enabled" type="bool" value="false"/>
  </property>
</channel>
X
HOME=$T/b python3 "$H"
[ "$(val "$T/b/.config/$C")" = 4 ] && grep -q 'dpms-enabled' "$T/b/.config/$C" && ok "existing file: added, other props kept" || bad "existing file"
# 3. user choice kept
sed -i 's/value="4"/value="1"/' "$T/b/.config/$C"; HOME=$T/b python3 "$H"
[ "$(val "$T/b/.config/$C")" = 1 ] && ok "user value 1 kept" || bad "user value overwritten"
# 4. idempotent
HOME=$T/a python3 "$H"; [ "$(grep -c power-button-action "$T/a/.config/$C")" = 1 ] && ok "idempotent" || bad "duplicated"
# 5. broken file left alone, never fails
mkdir -p "$(dirname "$T/c/.config/$C")"; echo '<channel' > "$T/c/.config/$C"
HOME=$T/c python3 "$H" && [ "$(cat "$T/c/.config/$C")" = '<channel' ] && ok "malformed file untouched, exit 0" || bad "malformed file"
# 6. root: no-op
[ "$(id -u)" != 0 ] && sudo -n true 2>/dev/null && { sudo env HOME=$T/r python3 "$H"; [ ! -e "$T/r" ] && ok "root: no-op" || bad "root wrote files"; }
# 7. live channel file also sets 4
grep -q '<property name="power-button-action" type="uint" value="4"/>' "$TOP/config/live/37omaxian-live" && ok "37omaxian-live: value 4" || bad "37omaxian-live"
# 8. xfpm's conffile is not touched/diverted by any omaxian package
! grep -rqs "xfce4-power-manager.xml" "$TOP"/packages/*/debian/*.preinst "$TOP"/packages/*/debian/*.postrm "$TOP"/packages/*/debian/*.postinst \
	&& [ ! -e "$S/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml" ] && ok "xfpm conffile not diverted/shipped" || bad "xfpm conffile touched"
exit $fail
