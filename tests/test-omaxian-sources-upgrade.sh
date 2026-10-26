#!/bin/bash
# omaxian-base 0.1.6 -> 0.1.7 upgrade of the omaxian.sources conffile, with
# real dpkg in a throwaway overlay over a built rootfs (needs root).
#   sudo tests/test-omaxian-sources-upgrade.sh <old.deb> <new.deb> [rootfs]
set -u
cd "$(dirname "$0")/.."
OLD=$(realpath "$1"); NEW=$(realpath "$2"); LOWER=$(realpath "${3:-build/rootfs-base}")
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 2; }
SRC=/etc/apt/sources.list.d/omaxian.sources
NEWSRC=$(mktemp); dpkg-deb --fsys-tarfile "$NEW" | tar -xO ."$SRC" > "$NEWSRC"
pass=0; fail=0
ok() { echo "ok   $*"; pass=$((pass+1)); }; bad() { echo "FAIL $*"; fail=$((fail+1)); }
W=$(mktemp -d); M=$W/m
up() { mkdir -p $W/u $W/w $M; mount -t overlay overlay -o lowerdir=$LOWER,upperdir=$W/u,workdir=$W/w $M
	cp "$OLD" "$NEW" $M/tmp/; o=/tmp/${OLD##*/}; n=/tmp/${NEW##*/}
	# start from a pristine 0.1.6 (downgrading an unmodified 0.1.7 conffile gives the 0.1.6 text)
	chroot $M dpkg -i --force-depends --force-downgrade $o >/dev/null 2>&1 </dev/null || echo "!! old install failed"; }
down() { umount $M; rm -rf $W/u $W/w; }
D() { chroot $M env DEBIAN_FRONTEND=noninteractive dpkg "$@" </dev/null; }
left() { ls $M/etc/apt/sources.list.d/ $M/etc/apt/ | grep -E 'omaxian.sources\.(dpkg|ucf)' ; }
en() { grep -m1 '^Enabled:' "$1"; }

# 1 unmodified 0.1.6 file: replaced silently -> Enabled: yes, identical to the package file
up; grep -q '^Enabled: no$' $M$SRC || bad "precondition: 0.1.6 not pristine"
D -i --force-depends $n > $W/log 2>&1; rc=$?
[ $rc = 0 ] && cmp -s $M$SRC $NEWSRC && [ -z "$(left)" ] && ok "pristine 0.1.6 -> 0.1.7: enabled, new file, no prompt" || { bad "pristine (rc=$rc)"; cat $W/log; }
down
# 2 hand-enabled with the documented sed: no conffile prompt (stdin is /dev/null, no --force-conf*), stays enabled
up; sed -i 's/^Enabled: no/Enabled: yes/' $M$SRC
D -i --force-depends $n > $W/log 2>&1; rc=$?
[ $rc = 0 ] && cmp -s $M$SRC $NEWSRC && [ -z "$(left)" ] && grep -q "only switched to Enabled: yes" $W/log && ok "hand-enabled (sed) -> 0.1.7: enabled, new file, no prompt" || { bad "sed-enabled (rc=$rc)"; cat $W/log; }
down
# 3 hand-enabled plus another local change: normal dpkg handling; --force-confold keeps the admin's file (still enabled)
up; sed -i 's/^Enabled: no/Enabled: yes/; 1i # my mirror note' $M$SRC; cp $M$SRC $W/mine
D --force-confold -i --force-depends $n > $W/log 2>&1; rc=$?
[ $rc = 0 ] && cmp -s $M$SRC $W/mine && [ "$(en $M$SRC)" = "Enabled: yes" ] && [ -e $M$SRC.dpkg-dist ] && ok "customised+enabled: kept (confold), .dpkg-dist written" || { bad "custom enabled (rc=$rc)"; cat $W/log; }
down
# 4 customised and still disabled: the admin's file is kept with confold (not flipped behind their back)
up; sed -i '1i # keep it off' $M$SRC; cp $M$SRC $W/mine
D --force-confold -i --force-depends $n > $W/log 2>&1; rc=$?
[ $rc = 0 ] && cmp -s $M$SRC $W/mine && [ "$(en $M$SRC)" = "Enabled: no" ] && ok "customised+disabled: kept disabled (confold)" || { bad "custom disabled (rc=$rc)"; cat $W/log; }
down
# 5 customised, no --force-conf*: dpkg would prompt; non-interactive it must fail cleanly instead of silently overwriting
up; sed -i '1i # keep it off' $M$SRC; cp $M$SRC $W/mine
D -i --force-depends $n > $W/log 2>&1; rc=$?
cmp -s $M$SRC $W/mine && ok "customised, no conffile policy: admin file untouched (dpkg rc=$rc)" || { bad "custom no-policy"; cat $W/log; }
down
# 6 build-time diversion (scripts/build-rootfs.sh): upgrade lands at the diverted path, apt sees no omaxian.sources
up; P=/etc/apt/omaxian.sources.omaxian-build
chroot $M dpkg-divert --local --rename --divert $P --add $SRC >/dev/null
D -i --force-depends $n > $W/log 2>&1; rc=$?
a=$([ ! -e $M$SRC ] && cmp -s $M$P $NEWSRC && echo y)
chroot $M dpkg-divert --local --rename --divert $P --remove $SRC >/dev/null
[ $rc = 0 ] && [ "$a" = y ] && cmp -s $M$SRC $NEWSRC && [ ! -e $M$P ] && ok "build diversion: upgraded at diverted path, restored enabled" || { bad "diversion (rc=$rc a=$a)"; cat $W/log; }
down
# 7 0.1.7 -> 0.1.7 reinstall with the admin's "Enabled: no": kept (dpkg: conffile unchanged in the package)
up; D -i --force-depends $n >/dev/null 2>&1; sed -i 's/^Enabled: yes/Enabled: no/' $M$SRC
D -i --force-depends $n > $W/log 2>&1; rc=$?
[ $rc = 0 ] && [ "$(en $M$SRC)" = "Enabled: no" ] && ok "0.1.7 disabled by admin: reinstall keeps it disabled" || { bad "reinstall (rc=$rc)"; cat $W/log; }
down
rm -rf $W $NEWSRC
echo "$pass passed, $fail failed"; [ $fail = 0 ]
