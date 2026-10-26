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
# Like CH, but the root is set up with pivot_root (bwrap) instead of chroot: the
# kernel refuses new user namespaces inside a chroot, so Flatpak's apply_extra
# sandbox ("extra-data" apps such as Zoom) only works this way.
BW() { bwrap --bind "$R" / --dev-bind /dev /dev --proc /proc --ro-bind /sys /sys --tmpfs /run --tmpfs /tmp \
	--clearenv --setenv HOME /root --setenv TERM dumb --setenv LANG C.UTF-8 \
	--setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$@"; }
# Remove a rootfs safely: a killed earlier run can leave /dev /proc /sys bind
# mounts inside it, and a plain rm -rf would then delete the HOST's /dev nodes.
rm_rootfs() { local d=$1; [ -e "$d" ] || return 0
	"$TOPDIR/scripts/umount-chroot.sh" "$d" >/dev/null 2>&1 || true
	if awk -v r="$(realpath "$d")" '$2 == r || index($2, r "/") == 1 {f=1} END{exit !f}' /proc/mounts; then
		die "$d still has mounts; refusing to delete it"; fi
	rm -rf --one-file-system "$d"; }
stage() { local _stg=$1; shift; if [ -e "$ST/$_stg" ]; then msg "stage $_stg: done"; return; fi
	msg "stage $_stg"; "$@"; touch "$ST/$_stg"; }
cleanup() { "$TOPDIR/scripts/umount-chroot.sh" "$R" >/dev/null 2>&1 || true
	[ -n "${REPO_PID:-}" ] && kill "$REPO_PID" 2>/dev/null || true; }
trap cleanup EXIT
APT="apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
REPO_PORT=${REPO_PORT:-8098}

# omaxian-base (>= 0.1.7) ships /etc/apt/sources.list.d/omaxian.sources with
# "Enabled: yes" (https://apt.omaxian.org). The build must only use the local
# repo + build mirror (offline-capable, and no published package shadowing a
# freshly built one), so the file is dpkg-diverted out of sources.list.d for
# the whole build: dpkg keeps doing proper conffile handling at the diverted
# path, apt never reads it. s_finalize removes the diversion again.
OMX_SRC=/etc/apt/sources.list.d/omaxian.sources
OMX_PARK=/etc/apt/omaxian.sources.omaxian-build
park_omaxian_sources() {
	CH dpkg-divert --local --rename --divert "$OMX_PARK" --add "$OMX_SRC" >/dev/null
}
unpark_omaxian_sources() {
	CH dpkg-divert --local --rename --divert "$OMX_PARK" --remove "$OMX_SRC" >/dev/null
	[ ! -e "$R$OMX_PARK" ] || die "$OMX_PARK still there after removing the diversion"
	if CH dpkg-query -W -f '${Status}' omaxian-base 2>/dev/null | grep -q ' installed'; then
		[ -f "$R$OMX_SRC" ] || die "$OMX_SRC missing in the image"
		cmp -s "$R$OMX_SRC" "$TOPDIR/packages/omaxian-base/files$OMX_SRC" \
			|| warn "$OMX_SRC differs from packages/omaxian-base (old omaxian-base in the local repo?)"
		msg "omaxian.sources: $(grep -m1 '^Enabled:' "$R$OMX_SRC")"
	fi
}

serve_repo() { # local Omaxian repo over http, reachable from inside the chroot
	[ -d "$LOCALREPO/dists" ] || die "no local repo: run scripts/make-repo.sh"
	python3 -m http.server -b 127.0.0.1 -d "$LOCALREPO" "$REPO_PORT" >/dev/null 2>&1 & REPO_PID=$!
	sleep 1
}

s_bootstrap() {
	rm_rootfs "$R"; mkdir -p "$BUILDDIR/keyring"
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
	park_omaxian_sources
	install -m644 "$TOPDIR"/config/apt/preferences.d/*.pref "$R/etc/apt/preferences.d/"
	install -m644 "$TOPDIR"/config/apt/apt.conf.d/* "$R/etc/apt/apt.conf.d/"
	install -m644 "$TOPDIR/config/apt/keys/NexusSfan.pgp" "$TOPDIR/keys/public/omaxian-archive-keyring.pgp" "$R/usr/share/keyrings/"
	install -m644 "$TOPDIR/packages/omaxian-base/files/etc/apt/sources.list.d/xlibre-debian.sources" "$R/etc/apt/sources.list.d/"
	if [ ! -s "$R/etc/apt/sources.list" ]; then # re-run after finalize: back to the build mirror
		rm -f "$R/etc/apt/sources.list.d/devuan.sources"
		for s in "" -updates -security -backports; do echo "deb $BUILD_MIRROR $DEVUAN_SUITE$s $DEVUAN_COMPONENTS"; done > "$R/etc/apt/sources.list"
	fi
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
	# Our own packages may be rebuilt under an unchanged (unpublished) version; dist-upgrade
	# skips those, so always reinstall them from repo-local to pick up the current build.
	local own; own=$(CH dpkg-query -W -f '${Package} ${Status}\n' 'omaxian-*' | awk '/ installed$/{print $1}')
	[ -z "$own" ] || CH $APT install --reinstall $own
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
	# - and never with --retain-splash: S18 can win the race against the lightdm
	#   daemon (its initscript returns before lightdm looks for plymouth). A
	#   retained splash leaves tty1 in KD_GRAPHICS with no owner; the kernel then
	#   ignores every VT switch (change_console), X waits forever in
	#   VT_WAITACTIVE for vt7 and the boot "stops" on the splash (intermittent;
	#   gnome-boxes BIOS report, round-6 BIOS repro). lightdm never reuses
	#   plymouth's VT1 (minimum-vt 7) and quits it without retaining anyway.
	if [ -f "$R/etc/default/smartmontools" ] && ! grep -q '^smartd_opts=' "$R/etc/default/smartmontools"; then
		printf '\n# Omaxian OS: exit 0 (not 17) when no SMART-capable disk is found (VMs)\nsmartd_opts="-q nodev0"\n' \
			>> "$R/etc/default/smartmontools"
	fi
	if [ -f "$R/etc/init.d/plymouth" ] && grep -q '^[[:space:]]*/usr/bin/plymouth quit --retain-splash$' "$R/etc/init.d/plymouth"; then
		sed -i 's|^\([[:space:]]*\)/usr/bin/plymouth quit --retain-splash$|\1if /usr/bin/plymouth --ping; then /usr/bin/plymouth quit \|\| true; fi|' \
			"$R/etc/init.d/plymouth"
	fi
	# rootfs patched by an older build (quit --retain-splash behind --ping): drop the flag
	if [ -f "$R/etc/init.d/plymouth" ]; then
		sed -i 's#/usr/bin/plymouth quit --retain-splash || true; fi#/usr/bin/plymouth quit || true; fi#' "$R/etc/init.d/plymouth"
		grep -q 'plymouth --ping; then /usr/bin/plymouth quit || true; fi' "$R/etc/init.d/plymouth" || warn "plymouth initscript not patched"
		! grep -q -- '--retain-splash' "$R/etc/init.d/plymouth" || warn "plymouth initscript still uses --retain-splash"
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
	unpark_omaxian_sources
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
	rm_rootfs "$R"; cp -a "$BUILDDIR/rootfs-base" "$R"
	printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod +x "$R/usr/sbin/policy-rc.d"
	# Flatpaks preinstalled system-wide (firstboot only updates them)
	CH flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
	# One app at a time, via BW: "extra-data" apps (Zoom) run apply_extra under
	# bwrap. Anything that still fails is left to omaxian-firstboot (online).
	local a missing=()
	# + the optional groups' Flatpaks (Telegram; field 6 of optional-groups.list):
	# preinstalled too, omaxian-firstboot removes the ones not picked in Calamares
	for a in $(read_list "$TOPDIR/config/flatpaks.list") \
		$(bash "$TOPDIR/scripts/gen-netinstall.sh" --optional-flatpaks "$TOPDIR/config/optional-groups.list" /dev/stdout | read_list /dev/stdin | cut -d'|' -f2); do
		BW flatpak install --system -y --noninteractive flathub "$a" || missing+=("$a")
	done
	[ ${#missing[@]} = 0 ] || warn "flatpaks NOT preinstalled (firstboot installs them online): ${missing[*]}"
	# offline payload (user supplies payload/appimages/*.AppImage, payload/openra/{Content,maps})
	# Only the manifest's "bundled" rows are copied: "optional" ones (Extra apps,
	# downloaded after install when picked) and files no row matches stay out.
	mkdir -p "$R/usr/share/omaxian/payload/appimages"
	cp -a "$PAYLOADDIR/openra" "$R/usr/share/omaxian/payload/"
	find "$R/usr/share/omaxian/payload" -name .gitkeep -delete
	for x in settings.yaml logs replays player.oraid; do rm -rf "$R/usr/share/omaxian/payload/openra/$x"; done
	local id glob method source class rest f n=0 nomiss=()
	shopt -s nullglob nocaseglob
	while IFS=$'\t' read -r id glob method source class rest; do
		[[ -z $id || $id == \#* || ${class:-bundled} == optional ]] && continue
		f=( "$PAYLOADDIR"/appimages/$glob )
		[ ${#f[@]} -gt 0 ] || { nomiss+=("$id"); continue; }
		cp -a "${f[0]}" "$R/usr/share/omaxian/payload/appimages/"; n=$((n+1))
	done < "$TOPDIR/config/appimages.manifest"
	shopt -u nullglob nocaseglob
	[ ${#nomiss[@]} = 0 ] || warn "bundled AppImages missing from payload/appimages (firstboot fetches them online): ${nomiss[*]}"
	msg "payload: $n bundled AppImages ($(du -sh "$R/usr/share/omaxian/payload/appimages" | cut -f1))"
	[ "$n" -gt 0 ] || warn "payload/appimages is empty: the full ISO will have no offline AppImages"
	s_optional_pool
	# 7th Calamares group, full ISO only (offline pool): VoxType. Not offered
	# on the base ISO at all (it is not in any online archive).
	bash "$TOPDIR/scripts/gen-netinstall.sh" "$TOPDIR/config/optional-groups.list" \
		"$R/etc/calamares/modules/netinstall.conf" "$TOPDIR/config/optional-groups-full.list" \
		--appimages "$TOPDIR/config/appimages.manifest"
	full_only_pkgs | tr ' ' '\n' | sed '/^$/d' > "$R/etc/calamares/omaxian-offline-only.list"
	# marker for omaxian-firstboot: this system ships everything offline, so
	# first boot is complete without network once nothing is missing
	mkdir -p "$R/var/lib/omaxian"; date -Is > "$R/var/lib/omaxian/full-offline"
	rm -f "$R/usr/sbin/policy-rc.d"
	CH dpkg-query -W -f '${Package}\t${Version}\n' > "$OUTDIR/omaxian-$FLAVOR.packages"
}

full_only_pkgs() { grep -vE '^\s*(#|$)' "$TOPDIR/config/optional-groups-full.list" | cut -d'|' -f5 | tr '\n' ' '; }
s_optional_pool() { # full ISO: the netinstall groups as an offline apt pool
	local pool=/var/cache/omaxian/optional-pool pk vx
	pk=$(grep -vE '^\s*(#|$)' "$TOPDIR/config/optional-groups.list" | cut -d'|' -f5 | tr '\n' ' ')
	mkdir -p "$R$pool"
	# full-only group: the pinned, signature-verified upstream VoxType .deb +
	# our integration package (neither is in an archive)
	"$TOPDIR/scripts/fetch-voxtype.sh" "$R$pool"
	vx=$(ls "$OUTDIR"/debs/omaxian-voxtype_*_all.deb 2>/dev/null | tail -1)
	[ -n "$vx" ] || die "out/debs/omaxian-voxtype_*.deb missing: run scripts/build-packages.sh"
	cp "$vx" "$R$pool/"
	cat > "$R/etc/apt/sources.list.d/omaxian-build-pool.sources" <<EOS
Types: deb
URIs: $BUILD_MIRROR
Suites: $DEVUAN_SUITE $DEVUAN_SUITE-updates $DEVUAN_SUITE-security $DEVUAN_SUITE-backports
Components: $DEVUAN_COMPONENTS
EOS
	# only the build mirror: with the image's own https sources enabled too,
	# apt-get's failover after an "Ign" ran out of memory (13 GB, OOM-killed)
	local O=(-o Dir::Etc::sourcelist=sources.list.d/omaxian-build-pool.sources -o Dir::Etc::sourceparts=-)
	CH apt-get "${O[@]}" update
	# reuse debs from an earlier build (build/dl/optional-pool)
	mkdir -p "$BUILDDIR/dl/optional-pool"
	cp -n "$BUILDDIR"/dl/optional-pool/*.deb "$R$pool/" 2>/dev/null || true
	# everything the groups need on top of the base system (the base already
	# has the rest): download only, into the pool
	CH apt-get "${O[@]}" -y --download-only -o Dir::Cache::archives="$pool" install $pk
	# archive dependencies of the two local debs (xclip, libnotify-bin, ...);
	# no Recommends: wtype / wl-clipboard are Wayland-only
	CH apt-get "${O[@]}" -y --download-only --no-install-recommends -o Dir::Cache::archives="$pool" install \
		$(cd "$R" && ls ."$pool"/voxtype_*.deb ."$pool"/omaxian-voxtype_*.deb | sed 's|^\.||')
	# Calamares' packages module purges the live packages and autoremoves their
	# dependencies BEFORE it installs the picked groups; group dependencies that
	# only the live packages pulled in (krita: libxcb-res0, libqt6core5compat6)
	# would then be missing offline. Put those into the pool as well.
	local live gone need extra
	live=$(sed -n 's/^ *- \([a-z0-9][a-z0-9.+-]*\)$/\1/p' "$TOPDIR/packages/omaxian-calamares-settings/files/etc/calamares/modules/packages.conf" | tr '\n' ' ')
	gone=$(CH apt-get "${O[@]}" -s --purge remove --auto-remove $live | awk '$1=="Purg"||$1=="Remv"{print $2}' | sort -u)
	need=$(CH apt-cache "${O[@]}" depends --recurse --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances $pk | grep -v '^[ <]' | sort -u)
	extra=$(comm -12 <(echo "$gone") <(echo "$need") | tr '\n' ' ')
	msg "optional pool: live-only dependencies added: ${extra:-none}"
	[ -z "$extra" ] || CH sh -c "cd $pool && apt-get ${O[*]} download $extra"
	rm -rf "$R$pool/partial" "$R$pool/lock"
	local f; for f in "$R$pool"/*.deb; do # not the local debs (own cache / out/debs)
		case "${f##*/}" in voxtype_*|omaxian-voxtype_*) ;; *) cp -n "$f" "$BUILDDIR/dl/optional-pool/";; esac
	done
	CH sh -c "cd $pool && apt-ftparchive packages . > Packages"
	# offline sanity: every group (incl. the full-only one) resolves from the
	# pool + what is already installed, with no other source
	echo "deb [trusted=yes] file:$pool ./" > "$R/etc/apt/sources.list.d/omaxian-pool-check.list"
	local P=(-o Dir::Etc::sourcelist=sources.list.d/omaxian-pool-check.list -o Dir::Etc::sourceparts=-)
	CH apt-get "${P[@]}" update >/dev/null
	CH apt-get "${P[@]}" -s install $pk $(full_only_pkgs) > "$BUILDDIR/optional-pool-check.log" 2>&1 \
		|| { cat "$BUILDDIR/optional-pool-check.log"; die "optional pool does not resolve offline"; }
	msg "optional pool: offline resolve OK ($(grep -c '^Inst ' "$BUILDDIR/optional-pool-check.log") to install)"
	# the reused cache (build/dl/optional-pool) also holds debs no group needs any
	# more (a package dropped from a group, older versions): keep only what the
	# offline install uses + the live-only dependencies + the local VoxType debs
	local keep n=0; keep=$( { awk '$1=="Inst"{print $2}' "$BUILDDIR/optional-pool-check.log"; echo "$extra" | tr ' ' '\n'; } | sort -u)
	for f in "$R$pool"/*.deb; do
		case "${f##*/}" in voxtype_*|omaxian-voxtype_*) continue;; esac
		grep -qxF "$(dpkg-deb -f "$f" Package)" <<<"$keep" || { rm -f "$f"; n=$((n+1)); }
	done
	if [ "$n" -gt 0 ]; then
		msg "optional pool: dropped $n unused debs from the reused cache"
		CH sh -c "cd $pool && apt-ftparchive packages . > Packages"
		CH apt-get "${P[@]}" update >/dev/null
		CH apt-get "${P[@]}" -s install $pk $(full_only_pkgs) > "$BUILDDIR/optional-pool-check.log" 2>&1 \
			|| { cat "$BUILDDIR/optional-pool-check.log"; die "optional pool does not resolve offline after pruning"; }
		msg "optional pool: offline resolve OK after pruning ($(grep -c '^Inst ' "$BUILDDIR/optional-pool-check.log") to install)"
	fi
	rm -f "$R/etc/apt/sources.list.d/omaxian-pool-check.list"
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
"$TOPDIR/scripts/umount-chroot.sh" "$R" >/dev/null 2>&1 || true
msg "rootfs $FLAVOR ready: $(du -sh --one-file-system "$R" | cut -f1)"
