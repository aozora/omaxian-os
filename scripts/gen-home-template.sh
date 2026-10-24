#!/bin/bash
# Render the default Omaxian home (what install.sh + deploy.sh produce for a
# user) into <out>, without root. This becomes /usr/share/omaxian/home-template
# and /etc/skel, so every new user gets a home they own (fixes the spike's
# root-owned ~/.local).
#   gen-home-template.sh <omaxian-src> <out>
. "$(dirname "$0")/lib.sh"
SRC=$(realpath "$1"); OUT=$2
[ "$(id -u)" -ne 0 ] || die "run as a normal user (Omaxian scripts refuse root)"
T=$(mktemp -d /tmp/omaxian-home.XXXXXX)
mkdir -p "$T/home" "$T/run"; chmod 700 "$T/run"
msg "running omaxian install.sh + deploy.sh with HOME=$T/home"
env -i PATH=/usr/bin:/bin HOME="$T/home" USER=omaxian XDG_RUNTIME_DIR="$T/run" LANG=C.UTF-8 TERM=dumb \
	bash "$SRC/scripts/install.sh" > "$T/install.log" 2>&1 || { cat "$T/install.log"; die "install.sh failed"; }
env -i PATH=/usr/bin:/bin HOME="$T/home" USER=omaxian XDG_RUNTIME_DIR="$T/run" LANG=C.UTF-8 TERM=dumb \
	bash "$SRC/scripts/deploy.sh" > "$T/deploy.log" 2>&1 || { cat "$T/deploy.log"; die "deploy.sh failed"; }
# hardcoded build paths would break on the target
if grep -rIl --exclude-dir=themes "$T/home" "$T/home" 2>/dev/null | head -5 | grep -q .; then
	grep -rIl --exclude-dir=themes "$T/home" "$T/home" | head; die "home template contains build paths"
fi
rm -rf "$OUT"; mkdir -p "$(dirname "$OUT")"; mv "$T/home" "$OUT"
rm -rf "$T"
msg "home template: $(du -sh "$OUT" | cut -f1) in $OUT"
