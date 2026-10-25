#!/bin/bash
# Build the live root filesystem.   (run as root, e.g. sudo -E)
#   build-rootfs.sh base   -> $BUILDDIR/rootfs-base
#   build-rootfs.sh full   -> $BUILDDIR/rootfs-full (= base + preinstalled
#                             Flatpaks + offline AppImage/OpenRA payload)
# Stages are stamped in <rootfs>.stamps/ so an interrupted build resumes.
# On this box set BUILD_MIRROR=http://127.0.0.1:8099/merged (see tools/).
. "$(dirname "$0")/lib.sh"
[ "$(id -u)" -eq 0 ] || die "run as root (sudo -E $0 $*)"
need mmdebstrap chroot python3
FLAVOR=${1:-base}
R="$BUILDDIR/rootfs-$FLAVOR"; ST="$R.stamps"; mkdir -p "$ST"
LOG="$BUILDDIR/rootfs-$FLAVOR.log"
CH() { "$TOPDIR/scripts/chroot-run.sh" "$R" "$@"; }
stage() { local n=$1; shift; if [ -e "$ST/$n" ]; then msg "stage $n: done"; return; fi
	msg "stage $n"; "$@"; touch "$ST/$n"; }
cleanup() { "$TOPDIR/scripts/umount-chroot.sh" "$R" >/dev/null 2>&1 || true
	[ -n "${REPO_PID:-}" ] && kill "$REPO_PID" 2>/dev/null || true; }
trap cleanup EXIT
APT="apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
REPO_PORT=${REPO_PORT:-8098}

serve_repo() { # local Omaxian repo over http, reachable from inside the chroot
	[ -d "$LOCALREPO/dists" ] || die "no local repo: run scripts/make-repo.sh"
	python3 -m http.server -b 127.0.0.1 -d "$LOCALREPO" "$REPO_PORT" >/dev/null 2>&1 & REPO_PID=$!
	sleep 1
}

s_bootstrap() {
	rm -rf "$R"; mkdir -p "$BUILDDIR/keyring"
	cp "$TOPDIR/config/apt/keys/devuan-archive-keyring.pgp" "$BUILDDIR/keyring/devuan-archive-keyring.gpg"
	mmdebstrap --mode=root --variant=minbase --arch="$ARCH" \
		--keyring="$BUILDDIR/keyring" \
		--include=devuan-keyring,ca-certificates,sysvinit-core,eudev,locales,debconf-utils,apt-utils \
		--components="$(echo $DEVUAN_COMPONENTS | tr ' ' ,)" \
		"$DEVUAN_SUITE" "$R" \
		"deb $BUILD_MIRROR $DEVUAN_SUITE $DEVUAN_COMPONENTS" \
		"deb $BUILD_MIRROR $DEVUAN_SUITE-updates $DEVUAN_COMPONENTS" \
		"deb $BUILD_MIRROR $DEVUAN_SUITE-security $DEVUAN_COMPONENTS" \
		"deb $BUILD_MIRROR $DEVUAN_SUITE-backports $DEVUAN_COMPONENTS"
}

s_apt_setup() {
	# no daemons in the chroot
	printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod +x "$R/usr/sbin/policy-rc.d"
	install -m644 "$TOPDIR"/config/apt/preferences.d/*.pref "$R/etc/apt/preferences.d/"
	install -m644 "$TOPDIR"/config/apt/apt.conf.d/* "$R/etc/apt/apt.conf.d/"
	install -m644 "$TOPDIR/config/apt/keys/NexusSfan.pgp" "$TOPDIR/keys/public/omaxian-archive-keyring.pgp" "$R/usr/share/keyrings/"
	install -m644 "$TOPDIR/packages/omaxian-base/files/etc/apt/sources.list.d/xlibre-debian.sources" "$R/etc/apt/sources.list.d/"
	cat > "$R/etc/apt/sources.list.d/omaxian-build.list" <<EOS
deb [signed-by=/usr/share/keyrings/omaxian-archive-keyring.pgp] http://127.0.0.1:$REPO_PORT $OMAXIAN_APT_SUITE main
EOS
	printf 'Package: *\nPin: release o=apt.omaxian.org\nPin-Priority: 700\n' > "$R/etc/apt/preferences.d/41-omaxian-build.pref"
	echo 'Acquire::https::Pipeline-Depth "0";' > "$R/etc/apt/apt.conf.d/91omaxian-build"
	# build only: never pull the big Noto extra packs (not even via Recommends)
	printf 'Package: fonts-noto-extra fonts-noto-ui-extra fonts-noto-cjk-extra fonts-noto\nPin: release *\nPin-Priority: -1\n' \
		> "$R/etc/apt/preferences.d/42-omaxian-build-nofonts.pref"
	# live image: no docs/man pages, en+it translations only (see the file)
	install -D -m644 "$TOPDIR/config/dpkg/90omaxian-live-excludes" "$R/etc/dpkg/dpkg.cfg.d/90omaxian-live-excludes"
	cp "$TOPDIR/config/debconf/preseed.cfg" "$R/tmp/preseed.cfg"
	CH debconf-set-selections /tmp/preseed.cfg
	sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/; s/^# *\(it_IT.UTF-8 UTF-8\)/\1/' "$R/etc/locale.gen"
	CH locale-gen
	echo "LANG=$DEFAULT_LOCALE" > "$R/etc/default/locale"
	echo "$LIVE_HOSTNAME" > "$R/etc/hostname"
	CH apt-get update
}

s_prefetch() { # optional: PREFETCH=1 [DEB_SEED=/old/apt/archives]
	[ "${PREFETCH:-0}" = 1 ] || return 0
	"$TOPDIR/tools/prefetch-debs.sh" "$R" "$TOPDIR/config/package-lists" "${DEB_SEED:-}"
}

inst() { # install package list files (in batches to keep apt's RAM low)
	local pk; pk=$(cd "$TOPDIR/config/package-lists" && read_list "$@" | tr '\n' ' ')
	CH $APT install $pk
}
s_base()    { inst 00-base.list; }
s_xlibre()  { inst 10-xlibre.list 20-audio.list; }
s_desktop() { inst 30-desktop.list; }
s_fonts()   { # fonts without Recommends (they drag in the Noto extra packs)
	local pk; pk=$(cd "$TOPDIR/config/package-lists" && read_list 35-fonts.list | tr '\n' ' ')
	CH $APT install --no-install-recommends $pk
}
s_user()    { inst 40-user.list; }
s_omaxian() { CH apt-get update; inst 50-omaxian.list; }
s_extrepo() {
	CH extrepo enable brave_release
	CH extrepo enable librewolf
	CH apt-get update
	inst 60-extrepo.list
}
s_live()    { inst 90-live.list
	# GRUB platform packages for the installed system (calamares-post picks one)
	mkdir -p "$R/var/cache/omaxian/grub-debs"
	CH sh -c 'cd /var/cache/omaxian/grub-debs && apt-get download grub-pc grub-efi-amd64'
}

s_upgrade() { # apply pins (backports kernel/pipewire/quickshell) and drop older kernels
	CH $APT dist-upgrade
	local old; old=$(CH dpkg-query -W -f '${Package} ${Status}\n' 'linux-image-[0-9]*' | awk '/installed$/ && $1 !~ /^linux-image-7\./{print $1}')
	[ -z "$old" ] || CH $APT purge $old
	CH dpkg-query -W -f '${Package} ${Version}\n' linux-image-amd64 pipewire wireplumber quickshell
}

s_configure() {
	# Live session: user, groups, autologin into the Omaxian session
	mkdir -p "$R/etc/live/config.conf.d"
	cat > "$R/etc/live/config.conf.d/omaxian.conf" <<EOC
LIVE_HOSTNAME="$LIVE_HOSTNAME"
LIVE_USERNAME="$LIVE_USER"
LIVE_USER_FULLNAME="Omaxian Live"
LIVE_USER_DEFAULT_GROUPS="audio cdrom dip floppy video plugdev netdev powerdev scanner bluetooth lpadmin sudo kvm libvirt"
LIVE_LOCALES="$DEFAULT_LOCALE"
LIVE_KEYBOARD_MODEL="pc105"
LIVE_KEYBOARD_LAYOUTS="us,it"
LIVE_KEYBOARD_OPTIONS="grp:alt_shift_toggle"
LIVE_TIMEZONE="$DEFAULT_TIMEZONE"
LIVE_UTC="yes"
EOC
	# default clock: $DEFAULT_TIMEZONE, hardware clock in UTC (Calamares overrides on install)
	echo "$DEFAULT_TIMEZONE" > "$R/etc/timezone"
	ln -sf "/usr/share/zoneinfo/$DEFAULT_TIMEZONE" "$R/etc/localtime"
	printf '0.0 0 0.0\n0\nUTC\n' > "$R/etc/adjtime"
	# live-only X session tweaks (no idle lock / screen blanking)
	install -m 0644 "$TOPDIR/config/live/37omaxian-live" "$R/etc/X11/Xsession.d/37omaxian-live"
	# remove any default games that slipped in (they are pinned -1 as well)
	local games; games=$(awk '/^Package:/{for(i=2;i<=NF;i++)print $i}' "$TOPDIR/config/apt/preferences.d/30-omaxian-nogames.pref")
	local inst_games; inst_games=$(CH dpkg-query -W -f '${Package} ${Status}\n' $games 2>/dev/null | awk '/ installed$/{print $1}' || true)
	[ -n "$inst_games" ] && CH $APT purge $inst_games
	# no Firefox, no systemd, no PulseAudio, no Xorg server
	for p in firefox firefox-esr systemd systemd-sysv pulseaudio xserver-xorg-core; do
		if CH dpkg-query -W -f '${Status}' "$p" 2>/dev/null | grep -q ' installed'; then die "$p got installed"; fi
	done
	# services (sysvinit)
	for s in lightdm network-manager elogind dbus bluetooth cups libvirtd omaxian-firstboot; do
		[ -e "$R/etc/init.d/$s" ] && CH update-rc.d "$s" defaults >/dev/null 2>&1 || true
	done
	# Boot without "startpar: service(s) returned failure: smartmontools plymouth":
	# - smartd exits 17 when no disk supports SMART (VMs, virtio/NVMe without
	#   SMART); -q nodev0 makes that a clean exit 0 (real disks are still monitored).
	# - lightdm (S04) already quits plymouthd when X starts, so the plymouth
	#   initscript's "plymouth quit --retain-splash" (S18, under set -e) fails
	#   when no daemon is left; only quit when plymouthd still answers.
	if [ -f "$R/etc/default/smartmontools" ] && ! grep -q '^smartd_opts=' "$R/etc/default/smartmontools"; then
		printf '\n# Omaxian OS: exit 0 (not 17) when no SMART-capable disk is found (VMs)\nsmartd_opts="-q nodev0"\n' \
			>> "$R/etc/default/smartmontools"
	fi
	if [ -f "$R/etc/init.d/plymouth" ] && grep -q '^[[:space:]]*/usr/bin/plymouth quit --retain-splash$' "$R/etc/init.d/plymouth"; then
		sed -i 's|^\([[:space:]]*\)/usr/bin/plymouth quit --retain-splash$|\1if /usr/bin/plymouth --ping; then /usr/bin/plymouth quit --retain-splash \|\| true; fi|' \
			"$R/etc/init.d/plymouth"
		grep -q 'plymouth --ping; then /usr/bin/plymouth quit' "$R/etc/init.d/plymouth" || warn "plymouth initscript not patched"
	fi
	# - xlibre-x11-common takes over the /etc/init.d/x11-common conffile from
	#   Debian's x11-common (removed, left in state rc); the takeover keeps the
	#   old file with mode 0644, so startpar cannot exec it at S19:
	#   "startpar: service(s) returned failure: x11-common ... failed!"
	if [ -f "$R/etc/init.d/x11-common" ] && [ ! -x "$R/etc/init.d/x11-common" ]; then
		chmod 0755 "$R/etc/init.d/x11-common"
	fi
	# Plymouth theme + initramfs (live-boot hooks are in now)
	CH plymouth-set-default-theme omaxian || warn "plymouth theme not set"
	CH update-initramfs -u -k all
	# release files
	cp "$R/etc/omaxian-release" "$R/etc/issue.omaxian" 2>/dev/null || true
	printf 'Omaxian OS %s (%s) \\n \\l\n\n' "$OMAXIAN_VERSION" "$OMAXIAN_CODENAME" > "$R/etc/issue"
}

strip_excluded() { # files unpacked before the dpkg excludes were in place (bootstrap)
	local d="$R/usr/share"
	find "$d/doc" -mindepth 1 ! -name copyright ! -type d -delete 2>/dev/null || true
	find "$d/doc" -mindepth 1 -type d -empty -delete 2>/dev/null || true
	rm -rf "$d"/man/* "$d"/info/* "$d"/gtk-doc/* "$R"/var/cache/man/*
	find "$d/help" -mindepth 1 -maxdepth 1 ! -name C ! -name it -exec rm -rf {} + 2>/dev/null || true
	find "$d/locale" -mindepth 1 -maxdepth 1 ! -name locale.alias ! -name 'en' ! -name 'en_*' ! -name it -exec rm -rf {} + 2>/dev/null || true
}

s_finalize() {
	# official sources for the shipped system
	rm -f "$R/etc/apt/sources.list.d/omaxian-build.list" "$R/etc/apt/preferences.d/41-omaxian-build.pref" \
		"$R/etc/apt/preferences.d/42-omaxian-build-nofonts.pref" \
		"$R/etc/apt/apt.conf.d/91omaxian-build"
	: > "$R/etc/apt/sources.list"
	cat > "$R/etc/apt/sources.list.d/devuan.sources" <<EOS
Types: deb
URIs: $DEVUAN_MIRROR
Suites: $DEVUAN_SUITE $DEVUAN_SUITE-updates $DEVUAN_SUITE-security $DEVUAN_SUITE-backports
Components: $DEVUAN_COMPONENTS
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
EOS
	[ -e "$R/usr/share/keyrings/devuan-archive-keyring.gpg" ] || sed -i '/^Signed-By/d' "$R/etc/apt/sources.list.d/devuan.sources"
	rm -f "$R/usr/sbin/policy-rc.d" "$R/tmp/preseed.cfg"
	CH apt-get clean
	strip_excluded
	rm -rf "$R"/var/lib/apt/lists/* "$R"/var/cache/apt/*.bin "$R"/tmp/* "$R"/root/.cache
	: > "$R/etc/machine-id"; rm -f "$R/var/lib/dbus/machine-id"
	find "$R/var/log" -type f -exec truncate -s0 {} +
	CH dpkg-query -W -f '${Package}\t${Version}\n' > "$OUTDIR/omaxian-$FLAVOR.packages"
}

s_full_from_base() {
	[ -e "$BUILDDIR/rootfs-base.stamps/finalize" ] || die "build the base rootfs first"
	rm -rf "$R"; cp -a "$BUILDDIR/rootfs-base" "$R"
	printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod +x "$R/usr/sbin/policy-rc.d"
	# Flatpaks preinstalled system-wide (firstboot only updates them)
	CH flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
	CH flatpak install --system -y --noninteractive flathub $(read_list "$TOPDIR/config/flatpaks.list")
	# offline payload (user supplies payload/appimages/*.AppImage, payload/openra/{Content,maps})
	mkdir -p "$R/usr/share/omaxian/payload"
	cp -a "$PAYLOADDIR/appimages" "$PAYLOADDIR/openra" "$R/usr/share/omaxian/payload/"
	find "$R/usr/share/omaxian/payload" -name .gitkeep -delete
	for x in settings.yaml logs replays player.oraid; do rm -rf "$R/usr/share/omaxian/payload/openra/$x"; done
	n=$(find "$R/usr/share/omaxian/payload/appimages" -maxdepth 1 -iname '*.AppImage' | wc -l)
	[ "$n" -gt 0 ] || warn "payload/appimages is empty: the full ISO will have no offline AppImages"
	s_optional_pool
	rm -f "$R/usr/sbin/policy-rc.d"
	CH dpkg-query -W -f '${Package}\t${Version}\n' > "$OUTDIR/omaxian-$FLAVOR.packages"
}

s_optional_pool() { # full ISO: the netinstall groups as an offline apt pool
	local pool=/var/cache/omaxian/optional-pool pk
	pk=$(grep -vE '^\s*(#|$)' "$TOPDIR/config/optional-groups.list" | cut -d'|' -f5 | tr '\n' ' ')
	mkdir -p "$R$pool"
	cat > "$R/etc/apt/sources.list.d/omaxian-build-pool.sources" <<EOS
Types: deb
URIs: $BUILD_MIRROR
Suites: $DEVUAN_SUITE $DEVUAN_SUITE-updates $DEVUAN_SUITE-security $DEVUAN_SUITE-backports
Components: $DEVUAN_COMPONENTS
EOS
	CH apt-get update
	# everything the groups need on top of the base system (the base already
	# has the rest): download only, into the pool
	CH apt-get -y --download-only -o Dir::Cache::archives="$pool" install $pk
	rm -rf "$R$pool/partial" "$R$pool/lock"
	CH sh -c "cd $pool && apt-ftparchive packages . > Packages"
	rm -f "$R/etc/apt/sources.list.d/omaxian-build-pool.sources"; rm -rf "$R"/var/lib/apt/lists/*
	msg "optional pool: $(ls "$R$pool"/*.deb | wc -l) debs, $(du -sh "$R$pool" | cut -f1)"
}

exec > >(tee -a "$LOG") 2>&1
msg "building $FLAVOR rootfs in $R (mirror $BUILD_MIRROR) at $(date)"
if [ "$FLAVOR" = full ]; then
	stage full s_full_from_base
else
	stage bootstrap s_bootstrap
	serve_repo
	stage apt-setup s_apt_setup
	stage prefetch s_prefetch
	stage base s_base
	stage xlibre s_xlibre
	stage desktop s_desktop
	stage fonts s_fonts
	stage user s_user
	stage omaxian s_omaxian
	stage extrepo s_extrepo
	stage live s_live
	stage upgrade s_upgrade
	stage configure s_configure
	stage finalize s_finalize
fi
msg "rootfs $FLAVOR ready: $(du -sh "$R" | cut -f1)"
