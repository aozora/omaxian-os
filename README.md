# Omaxian OS

**Release 0.1 "Trans-Siberian Shaman"** (os-release `VERSION="0.1 (Trans-Siberian Shaman)"`,
`VERSION_CODENAME=trans-siberian-shaman`; the Devuan base codename is in
`DEVUAN_CODENAME=excalibur` / `DEBIAN_CODENAME=trixie`, apt keeps using its own
sources).

A Devuan 6 "Excalibur" based live/installable distribution with the
[Omaxian](https://github.com/aozora/omaxian) desktop (v1.1, Omarchy vendored)
as the default session and XFCE as the alternative. No systemd: sysvinit + eudev
+ elogind, XLibre X server, PipeWire per user, kernel 7.2 from excalibur-backports.

Two images are made:

| ISO | Contents |
|---|---|
| `omaxian-base-0.1-trans-siberian-shaman-amd64.iso` | desktop + core apps; the optional app groups (Chromium, Thunderbird, Graphics, Flatpaks Telegram / Discord / Packet / Gear Lever, Containers, Virtualization, AppImages LocalSend / ElecWhat / Obsidian / MarkText, all ticked by default) are picked on the installer's Applications page and installed from the network, or by the first-boot service when offline; Flatpaks and AppImages are fetched on first boot (the picked ones), except ONLYOFFICE (AppImage bundled, in `~/AppImages` with a menu entry from the first login) |
| `omaxian-full-0.1-trans-siberian-shaman-amd64.iso` | same plus an offline pool for the optional groups and a 7th, unselected group **Voice dictation (VoxType)** (full ISO only, docs/voxtype.md), Flatpaks preinstalled (Telegram, Discord, Packet, Gear Lever too; removed on first boot when unticked) and `payload/` (10 AppImages, OpenRA content) bundled for offline install |

The live image has no man pages/docs and only en/it translations (dpkg
path-excludes, live only); installed systems get the normal dpkg policy back,
`sudo omaxian-restore-docs` reinstalls the stripped files.

Both boot BIOS and UEFI (hybrid grub-mkrescue image, GRUB theme), run a live
session (live-boot + live-config-sysvinit, user `omaxian`) and install with
Calamares (branding `omaxian`), which removes the live packages and installs
grub-pc or grub-efi-amd64 to match the firmware.

## Layout

```
config/            build.conf, apt sources/prefs/keys, package-lists/*.list,
                   debconf preseed, flatpaks.list, appimages.manifest
packages/          debian packaging of the Omaxian OS packages
  omaxian-base               apt sources/pins/keyrings, os defaults, groups
  omaxian-branding           Plymouth "omaxian", GRUB theme, LightDM gtk-greeter theme, wallpapers
  omaxian-session            Omaxian v1.1 + Omarchy (vendored), session + home template
                             (seeds community-apps: disktree, monologue,
                             omarchy-meeting-recorder, signed)
  omaxian-strata             Strata file manager (signed release), default for inode/directory
  omaxian-firstboot          firstboot init script: flathub + flatpaks, AppImage refresh;
                             per-user first run: OpenRA content, Gear Lever integration;
                             omaxian-optional (add optional groups/apps later)
  omaxian-calamares-settings Calamares settings/modules, post-install script
scripts/           fetch-*, build-packages, make-repo (reprepro), build-rootfs,
                   build-iso, boot-test (QEMU), publish-r2, gen-test-key, mirror-xlibre
tools/             qmon.py (QEMU monitor: screenshots/keys), prefetch-debs.sh, devuan-redirect-proxy.py
payload/           (git-ignored) appimages/*.AppImage, openra/{Content,maps}
ci/github/         GitHub Actions sketch
docs/              signing-key.md, missing-packages.md, netinstall-TODO.md, voxtype.md
```

## Build

Host: Debian/Devuan with `mmdebstrap reprepro squashfs-tools xorriso grub-pc-bin
grub-efi-amd64-bin mtools dpkg-dev debhelper rsync jq gnupg qemu-system-x86 ovmf`.

```sh
make keys          # throwaway TEST key (real key: docs/signing-key.md)
make packages repo # out/debs + signed repo-local/
make base          # sudo: build/rootfs-base -> out/omaxian-base-*.iso
make test-base     # QEMU boot test, PNGs in shots/  (FW=bios|uefi SECS=900)
# full ISO: put AppImages in payload/appimages and OpenRA Content+maps in payload/openra
make full
```

Each rootfs stage leaves a stamp in `build/rootfs-<flavor>.stamps/`; re-running
resumes there. Useful environment variables: `BUILD_MIRROR` (local cache/proxy),
`PREFETCH=1` (parallel .deb download), `DEB_SEED=<dir of .debs>`,
`ACCEL=kvm|tcg`, `RAM`, `DISK=<qcow2>` (install test).

`build-rootfs.sh` refuses an image that ended up with firefox, systemd,
pulseaudio or the real Xorg server.

## Apt repository

The repo is live at https://apt.omaxian.org: since omaxian-base 0.1.7 images ship
`/etc/apt/sources.list.d/omaxian.sources` with `Enabled: yes` (upgrades from
0.1.6 enable it too unless the file was customised; see the 0.1.7 changelog).
During the rootfs build that file is dpkg-diverted out of `sources.list.d`, so
build-time apt only uses the local repo and the build mirror; `s_finalize`
puts it back.

## First boot

- `omaxian-firstboot` (sysvinit, runs once, not in the live session): waits for
  network (in background, as long as the machine is up; unfinished steps retry at the next boot), adds Flathub, installs `flatpaks.list` plus the optional groups'
  Flatpaks picked in the installer (Telegram, Discord, Packet, Gear Lever: field 6 of
  `config/optional-groups.list`, pick recorded in /var/lib/omaxian/optional-flatpaks.list;
  the full ISO preinstalls them and removes the unpicked ones offline), refreshes AppImages from
  `appimages.manifest` (methods github/json/url; `payload` rows have no known
  upstream URL and are reported as `?? id` in /var/log/omaxian-firstboot.log).
- AppImages (`config/appimages.manifest`, column 5 = class): 10 **bundled** in the
  full ISO payload (BleachBit, ElecWhat, LocalSend, MarkText, Obsidian, ONLYOFFICE,
  OpenRA Dune 2000 / Red Alert / Tiberian Dawn, Task Manager); ONLYOFFICE is class
  **base**: bundled in the base ISO too (build stage `payload`) and never
  re-downloaded by firstboot (Gear Lever updates it). ElecWhat, LocalSend, MarkText
  and Obsidian are class **pick**: bundled in the full ISO but each also a ticked
  checkbox in the installer group **Apps (AppImages)**: unticked ones are not
  downloaded (base) or copied to `~/AppImages` (full). 6 **optional**
  ones never bundled in any ISO: Cursor, Grok Bot, Rebased, RustDesk, Shotcut,
  Teams for Linux. Each optional one is its own checkbox (unselected) in the
  installer's Applications-page group **Extra apps (downloaded after install)**;
  the pick is recorded in /var/lib/omaxian/optional-appimages.list
  (netinstall marker `omaxian-pick:appimage:<id>`, recorded by the Calamares job
  `omaxianpicks` before the packages module) and firstboot downloads the picked ones once
  online (GitHub ones pinned to a release asset + its sha256; Cursor and Grok Bot
  follow their official release feed, no checksum published), then they land in
  `~/AppImages`. On the full ISO a picked extra app counts as pending: firstboot.done
  is not written offline, and firstboot retries at every boot until online.
  Nothing picked: the full ISO finishes firstboot offline as before.
- `omaxian-user-firstrun` (each user's first X session): seeds `~/.config/openra`
  (Content + maps only), copies AppImages to `~/AppImages`, integrates them with Gear Lever.
  Until Gear Lever is installed (base ISO before the first online boot) an AppImage
  gets a plain menu entry from its own `.desktop` and icon
  (`~/.local/share/applications/omaxian-appimage-<id>.desktop`), removed once
  Gear Lever integrates it. Gear Lever unticked in the installer: the plain entries stay.
- Every login (`omaxian-user-setup`) runs `xdg-user-dirs-update`: Desktop,
  Documents, Downloads, Music, Pictures, Videos, Templates, Public in the session
  language (e.g. Documenti, Scaricati, ... with `it_IT`).

## Optional groups and apps

The installer's **Applications** page (Calamares netinstall, generated from
`config/optional-groups.list` + `config/optional-groups-full.list` by
`scripts/gen-netinstall.sh`) offers these groups:

| Group id | Name | Contains | Ticked by default | Base ISO | Full ISO |
|---|---|---|---|---|---|
| `browser-chromium` | Chromium | `chromium` | yes | network | offline pool |
| `mail-thunderbird` | Thunderbird | `thunderbird` | yes | network | offline pool |
| `graphics` | Graphics | `gimp inkscape krita` | yes | network | offline pool |
| `chat-telegram` | Telegram | Flatpak `org.telegram.desktop` | yes | Flathub at first boot | preinstalled (removed if unticked) |
| `chat-discord` | Discord | Flatpak `com.discordapp.Discord` | yes | Flathub at first boot | preinstalled (removed if unticked) |
| `share-packet` | Packet | Flatpak `io.github.nozwock.Packet` (Quick Share) | yes | Flathub at first boot | preinstalled (removed if unticked) |
| `gearlever` | Gear Lever | Flatpak `it.mijorus.gearlever` (AppImage manager) | yes | Flathub at first boot | preinstalled (removed if unticked) |
| `containers` | Containers | `podman podman-docker podman-compose buildah docker-compose distrobox` + Flatpak `io.podman_desktop.PodmanDesktop` | yes | network | offline pool (+ Flatpak preinstalled) |
| `virtualization` | Virtualization | `qemu-system-x86 qemu-system-gui qemu-utils libvirt-daemon-system libvirt-clients libvirt-daemon libvirt-daemon-driver-qemu bridge-utils virt-manager gnome-boxes spice-client-gtk` | yes | network | offline pool |
| `voice-voxtype` | Voice dictation (VoxType) | upstream `voxtype` .deb (pinned) + `omaxian-voxtype` | no | not in the installer (add later) | offline pool |
| (one per app: `elecwhat` `localsend` `marktext` `obsidian`) | Apps (AppImages) | AppImages ElecWhat, LocalSend, MarkText, Obsidian | yes | downloaded at first boot | bundled (copied to `~/AppImages` if ticked) |
| (one per app) | Extra apps (downloaded after install) | AppImages Cursor, Grok Bot, Rebased, RustDesk, Shotcut, Teams for Linux | no | downloaded at first boot | downloaded at first boot |

"network": installed by Calamares when the machine is online during the
install, otherwise recorded and installed by `omaxian-firstboot` at the first
online boot. Of the 10 bundled AppImages (see First boot) BleachBit, OpenRA
and Task Manager are always installed on the full ISO and downloaded at first
boot on the base ISO, ONLYOFFICE is bundled in both, the four **pick** ones follow
their checkbox.

### Adding a group or app later: `omaxian-optional`

On an installed system (needs network for apt, Flathub and downloads):

```sh
omaxian-optional                   # interactive (menu: "Add optional apps")
omaxian-optional list              # groups and AppImages, with status
omaxian-optional install containers voice-voxtype shotcut
omaxian-optional install chat-discord gearlever obsidian   # unticked in the installer
```

It asks for the password (sudo in a terminal, pkexec otherwise), installs the
group's apt packages one per apt run, its Flatpaks from Flathub (system-wide),
VoxType from the pinned upstream .deb (sha256-checked) plus `omaxian-voxtype`
(shipped in `/usr/share/omaxian/payload/debs`), downloads the AppImages that are
not bundled (`omaxian-appimage-fetch`, only the requested ids) and copies them to
the calling user's `~/AppImages` (Gear Lever integration or a plain menu entry).
It updates firstboot's records in /var/lib/omaxian, so firstboot never removes
what was added. Log: /var/log/omaxian-optional.log.

The same by hand:

```sh
sudo apt update
sudo apt install chromium                    # browser-chromium
sudo apt install thunderbird                 # mail-thunderbird
sudo apt install gimp inkscape krita         # graphics
sudo apt install podman podman-docker podman-compose buildah docker-compose distrobox   # containers
sudo apt install qemu-system-x86 qemu-system-gui qemu-utils libvirt-daemon-system libvirt-clients \
  libvirt-daemon libvirt-daemon-driver-qemu bridge-utils virt-manager gnome-boxes spice-client-gtk  # virtualization
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak install -y flathub org.telegram.desktop               # chat-telegram
sudo flatpak install -y flathub com.discordapp.Discord             # chat-discord
sudo flatpak install -y flathub io.github.nozwock.Packet           # share-packet
sudo flatpak install -y flathub it.mijorus.gearlever               # gearlever
sudo flatpak install -y flathub io.podman_desktop.PodmanDesktop    # containers (GUI)
# voice-voxtype: URL and sha256 in /usr/share/omaxian/voxtype.pin
. /usr/share/omaxian/voxtype.pin; cd /tmp && curl -fLO "$VOXTYPE_URL" \
  && echo "$VOXTYPE_SHA256  ${VOXTYPE_URL##*/}" | sha256sum -c \
  && sudo apt install "./${VOXTYPE_URL##*/}" /usr/share/omaxian/payload/debs/omaxian-voxtype_*_all.deb
# an AppImage (id from appimages.manifest), e.g. shotcut (or obsidian, localsend, ...):
sudo omaxian-optional-appimage select shotcut     # extra apps only
sudo OMAXIAN_APPIMAGE_ONLY=shotcut omaxian-appimage-fetch /var/lib/omaxian/appimages
OMAXIAN_FIRSTRUN_ONLY=shotcut omaxian-user-firstrun  # into ~/AppImages (log: ~/.local/state/omaxian/user-firstrun.log)
```

### Round 16 status (2026-11-08)

Round 16 published 2026-11-09 CET: GitHub `omaxian-os-build` at `4adbeb3`; ISOs on download.omaxian.org/releases/0.1/; signed apt on apt.omaxian.org (session 1.1.0-2, base 0.1.9, Strata 1.2.0-1). Exact URLs, streamed hashes and checks: `docs/test-report-0.1.md` publish round 16.
