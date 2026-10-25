# Omaxian OS

**Release 0.1 "Trans-Siberian Shaman"** (os-release `VERSION="0.1 (Trans-Siberian Shaman)"`,
`VERSION_CODENAME=trans-siberian-shaman`; the Devuan base codename is in
`DEVUAN_CODENAME=excalibur` / `DEBIAN_CODENAME=trixie`, apt keeps using its own
sources).

A Devuan 6 "Excalibur" based live/installable distribution with the
[Omaxian](https://github.com/aozora/omaxian) desktop (v1.0.3, Omarchy vendored)
as the default session and XFCE as the alternative. No systemd: sysvinit + eudev
+ elogind, XLibre X server, PipeWire per user, kernel 7.2 from excalibur-backports.

Two images are made:

| ISO | Contents |
|---|---|
| `omaxian-base-0.1-trans-siberian-shaman-amd64.iso` | desktop + core apps; the optional app groups (Chromium, Thunderbird, Graphics, Telegram, Containers, Virtualization) are picked on the installer's Applications page and installed from the network, or by the first-boot service when offline; Flatpaks and AppImages are fetched on first boot |
| `omaxian-full-0.1-trans-siberian-shaman-amd64.iso` | same plus an offline pool for the optional groups, Flatpaks preinstalled and `payload/` (AppImages, OpenRA content) bundled for offline install |

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
  omaxian-session            Omaxian v1.0.3 + Omarchy (vendored), session + home template
  omaxian-strata             Strata file manager (signed release), default for inode/directory
  omaxian-firstboot          firstboot init script: flathub + flatpaks, AppImage refresh;
                             per-user first run: OpenRA content, Gear Lever integration
  omaxian-calamares-settings Calamares settings/modules, post-install script
scripts/           fetch-*, build-packages, make-repo (reprepro), build-rootfs,
                   build-iso, boot-test (QEMU), publish-r2, gen-test-key, mirror-xlibre
tools/             qmon.py (QEMU monitor: screenshots/keys), prefetch-debs.sh, devuan-redirect-proxy.py
payload/           (git-ignored) appimages/*.AppImage, openra/{Content,maps}
ci/github/         GitHub Actions sketch
docs/              signing-key.md, missing-packages.md, netinstall-TODO.md
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

## Publishing (Cloudflare R2)

| What | Bucket | URL |
|---|---|---|
| apt repo | `omaxian-apt` | https://apt.omaxian.org |
| ISOs | `omaxian-iso` | https://download.omaxian.org/releases/<ver>/ |

```sh
export R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... R2_ENDPOINT=https://<account>.r2.cloudflarestorage.com
DRY_RUN=1 scripts/publish-r2.sh apt    # default is dry-run
DRY_RUN=0 scripts/publish-r2.sh iso
```

It refuses to publish a repo signed with the test key. Images ship
`/etc/apt/sources.list.d/omaxian.sources` with `Enabled: no` until the repo is live.

## First boot

- `omaxian-firstboot` (sysvinit, runs once, not in the live session): waits for
  network, adds Flathub, installs `flatpaks.list`, refreshes AppImages from
  `appimages.manifest` (methods github/json/url; `payload` rows have no known
  upstream URL and are reported as `?? id` in /var/log/omaxian-firstboot.log).
- `omaxian-user-firstrun` (each user's first X session): seeds `~/.config/openra`
  (Content + maps only), copies AppImages to `~/AppImages`, integrates them with Gear Lever.
