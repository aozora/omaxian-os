#!/bin/bash
# Live installer discoverability: live-installer-hint setup/notify, and the
# Omaxian launcher ranking for "install" (uses the shell's AppSearch.js +
# hidden-entries.sh from build/src/omaxian when present, needs node).
set -u
T=$(cd "$(dirname "$0")/.." && pwd); P=$T/packages/omaxian-calamares-settings/files
H=$P/usr/libexec/omaxian/live-installer-hint
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; fail=0
ok() { echo "ok   $*"; }; ko() { echo "FAIL $*"; fail=1; }
# fake system data dir: stock calamares + gdebi + ours
mkdir -p "$W/share/applications" "$W/home/.config/i3/config.d" "$W/bin"
printf '[Desktop Entry]\nType=Application\nName=Install System\nExec=sh -c "pkexec calamares"\nKeywords=installer;\n' > "$W/share/applications/calamares.desktop"
printf '[Desktop Entry]\nType=Application\nName=GDebi Package Installer\nExec=gdebi-gtk\n' > "$W/share/applications/gdebi.desktop"
cp "$P/usr/share/applications/omaxian-install.desktop" "$W/share/applications/"
# hint uses /usr/share/applications/omaxian-install.desktop: run on a copy pointed at $P
sed "s|/usr/share/applications/omaxian-install.desktop|$P/usr/share/applications/omaxian-install.desktop|" "$H" > "$W/hint"; chmod +x "$W/hint"
HOME=$W/home PATH=/usr/bin:/bin "$W/hint" setup
grep -q '^NoDisplay=true' "$W/home/.local/share/applications/calamares.desktop" && ok "stock calamares.desktop hidden for the live user" || ko "calamares override"
grep -q 'bindsym Mod4+Shift+i exec --no-startup-id /usr/bin/omaxian-install' "$W/home/.config/i3/config.d/90-omaxian-live-installer.conf" && ok "i3 Super+Shift+I" || ko "i3 binding"
[ -x "$W/home/Desktop/omaxian-install.desktop" ] && ok "desktop shortcut" || ko "desktop shortcut"
# notify: once, with the Install action
printf '#!/bin/sh\necho "$*" >> %s/notify.log\n' "$W" > "$W/bin/notify-send"; chmod +x "$W/bin/notify-send"
HOME=$W/home PATH=$W/bin:/usr/bin:/bin "$W/hint" notify; HOME=$W/home PATH=$W/bin:/usr/bin:/bin "$W/hint" notify
[ "$(wc -l < "$W/notify.log")" = 1 ] && grep -q 'install=Install Omaxian OS' "$W/notify.log" && ok "one-time notification with Install action" || ko "notification ($(cat "$W/notify.log" 2>/dev/null))"
# Xsession hook is live-only and the installed system drops it
grep -q "grep -qw 'boot=live' /proc/cmdline" "$P/etc/X11/Xsession.d/38omaxian-live-installer" && ok "hook gated on boot=live" || ko "hook gate"
grep -q '38omaxian-live-installer' "$P/usr/libexec/omaxian/calamares-post" && ok "calamares-post removes the hook" || ko "calamares-post"
# launcher ranking
S=$T/build/src/omaxian/omaxian/.local/share/omarchy/shell/services
if command -v node >/dev/null && [ -f "$S/AppSearch.js" ] && [ -f "$S/hidden-entries.sh" ]; then
	hidden=$(HOME=$W/home XDG_DATA_DIRS=$W/share bash "$S/hidden-entries.sh" i3 | tr '\n' ',')
	first=$(node -e '
const S=require(process.argv[1]), fs=require("fs"), path=require("path");
const hidden=new Set(process.argv[3].split(",").filter(Boolean));
const d=process.argv[2], e=fs.readdirSync(d).map(f=>{const t=fs.readFileSync(path.join(d,f),"utf8");
 const g=k=>(t.match(new RegExp("^"+k+"=(.*)$","m"))||[])[1]||"";
 return {id:f.replace(/\.desktop$/,""),name:g("Name"),genericName:g("GenericName"),comment:g("Comment"),keywords:g("Keywords").split(";").filter(Boolean)}});
const r=S.sortedEntries(e,"install",x=>hidden.has(x.id)); console.log(r.map(x=>x.entry.id).join(" "));' "$S/AppSearch.js" "$W/share/applications" "$hidden")
	[ "${first%% *}" = omaxian-install ] && ok "\"install\" -> $first" || ko "ranking: $first (hidden: $hidden)"
else echo "skip ranking (no node or shell sources)"; fi
exit $fail
