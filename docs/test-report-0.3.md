# Omaxian OS 0.3 "Space Cat" — build + test report (round 19, 2026-11-25)

Built and tested locally. Nothing was published: no ISO upload, no apt publish, no announcement.

Shell: Omaxian v1.2.4 = `bdf53757b9916a631ac2f270a64f8f7fcc00d395` (tag v1.2.4).
Every community app, including flowtunes, fantasi and omarchy-local-ai, is installed from the shell CI pin (`apps-99b69ff`). The build refuses an app that would compile.
Base: Devuan 6 Excalibur + excalibur-backports, sysvinit + eudev + elogind.

`tests/test-space-cat.sh`: 36 passed, 0 failed.

## Artifacts

Local staging only: `/workspace/out/0.3/` (`SHA256SUMS` matches the table).
Packages: `/workspace/out/0.3/debs/`. Local signed apt repo: `/workspace/build/r19/repo` (throwaway build key, separate from the published apt key).

| File | Size | SHA-256 |
|---|---|---|
| omaxian-base-0.3-space-cat-amd64.iso | 3610511360 (3.4 GiB) | a65dc356fade58bdefcb54effc9f399a4e8e61c360eaec8c9e6ae0e4b96f0d68 |
| omaxian-full-0.3-space-cat-amd64.iso | 9343782912 (8.7 GiB) | 682d63d36ce8a8d5634bc5906ffff3a22d4588449b9e5b110932f79ec1d90466 |

Volume ids: `OMAXIAN_0_3_SPACE_CAT_BASE`, `OMAXIAN_0_3_SPACE_CAT_FULL`.

### Packages in the image

1986 packages on both flavors (the full image adds Flatpaks and `payload/`, not extra apt packages).

| Package | Version |
|---|---|
| omaxian-base | 0.3 |
| omaxian-branding | 0.3.2 |
| omaxian-calamares-settings | 0.3.1 |
| omaxian-firstboot | 0.3.0 |
| omaxian-session | 1.2.4-2 |
| omaxian-strata | 1.2.2-1 |
| omaxian-typecase | 0~git3119bed-1 |
| omaxian-fonts-nerd | 3.5.1-1 |
| omaxian-ydotool | 1.0.4-1 |
| omaxian-voxtype | 1.1.1-3 (full ISO payload) |
| chezmoi | 2.74.2 |
| rustic | 0.12.0-1 |
| mygo-music | 0.1.26 |
| linux-image-amd64 | 7.3.4-1~bpo13+1 (running 7.3.4+deb13-amd64) |
| mesa-libgallium | 26.1.6-1~bpo13+1 |
| pipewire | 1.6.9-2~bpo13+1 |
| quickshell | 0.3.0-1~bpo13+1 |
| xserver-xlibre | 1:7.8+5 |

Also installed: xsecurelock, shellcheck, heif-thumbnailer, qt6-image-formats-plugins, slop, chromium, the Podman stack (podman, crun, netavark, aardvark-dns, uidmap, passt), WebKitGTK, Qt Quick 3D. vlc, imv and nsxiv are pinned out and were absent on every install.

Community apps (18, in every user's home, sha256-pinned): aether, cards, checkmate, disktree, fantasi, flowtunes, folio, hype, monologue, omacalc, omacut, omarchy-local-ai, omarchy-meeting-recorder, omareel, omaview, omawrite, plain, signed.
Community plugins: 16 seeded and enabled. The PulseAudio speaker calibrator is copied and left disabled (the session is PipeWire).

Full ISO Flatpaks (preinstalled on the first try): protonmail-bridge, gpu_screen_recorder, Discord, g4music, Packet, PodmanDesktop, Gear Lever, Telegram, Zoom.
Ten bundled AppImages. OnlyOffice is class base, so it is in both ISOs.

### OpenRA content (full ISO)

`aws s3 ls` of `s3://omaxian-staging/openra/` returned no objects. The complete set was at the bucket root: `SHA256SUMS` and `openra.tar.part00` through `openra.tar.part07`. Part checksums (`sha256sum -c SHA256SUMS`) matched. The joined tar is 2320783360 bytes, sha256 `4ec0aca1f1215efa254718d2150e07961f9d3e51e201736f27416299f41d2325`. Extracted to `payload/openra/`, then the tar and the parts were deleted. The download was read-only. Nothing was uploaded to any bucket.

Extracted tree:

- `Content/cnc` 115 files, `Content/d2k` 590 files, `Content/ra` 151 files
- `maps/{cnc,d2k,ra}/release-20250330` directories are present and empty (stock maps ship inside the OpenRA AppImages; same layout as the 0.1 payload)
- `settings.yaml`, `logs`, `replays` and `player.oraid` are absent (`build-rootfs.sh` strips them)

`unsquashfs` of `omaxian-full-0.3-space-cat-amd64.iso` (squashfs at LBA 7070) lists `usr/share/omaxian/payload/openra/Content/{cnc,d2k,ra}` and `maps/{cnc,d2k,ra}`. The base rootfs has no `payload/openra` directory.

## VM tests

KVM, 3 GiB / 2 vCPU, no network, one VM at a time (`tools/diag/r19`). Offline install, file manager left on the default (Strata). Test media label `R19TEST`.

| VM | Test | Result |
|---|---|---|
| bu | base, UEFI live | PASS (146 checks, 0 FAIL) |
| bu | base, UEFI install to "All done", then installed boot | PASS (151 checks, 0 FAIL). Strata 1.2.2 running on the user's home. Calamares removed. Kernel 7.3.4, Mesa from backports. OmaView for image/jpeg and video/mp4, MyGo Music for audio/mpeg, PDF left off OmaView. typecase, chezmoi, rustic, mygo-music present. subuid/subgid allocated. 16 plugins. local-ai, flowtunes and fantasi PINNED/EXEC/QML pass. |
| bb | base, BIOS live | PASS (146 checks, 0 FAIL) |
| bb | base, BIOS install to "All done", then installed boot | PASS (152 checks, 0 FAIL), including `OPENRA_BASE_ABSENT_PASS` |
| fu | full, UEFI live | PASS (156 checks, 0 FAIL). OpenRA content and maps for cnc, d2k and ra, and the four stripped paths, all PASS |
| fu | full, UEFI install to "All done" (Restart now), then installed boot | PASS (161 checks, 0 FAIL). Same OpenRA checks PASS. Telegram flatpak present. Strata 1.2.2. Calamares removed. |
| fb | full, BIOS live | PASS (156 checks, 0 FAIL), OpenRA checks PASS |
| fb | full, BIOS install to "All done", then installed boot | PASS (161 checks, 0 FAIL), OpenRA checks PASS |

The OpenRA assertions were added to the test media after the base UEFI installed check. That install still has no `payload/openra` (confirmed on the base rootfs). The base BIOS install and both full installs ran the assertion.

## Not tested

- Real hardware, Secure Boot, and online first boot (updates, extra-app downloads).
- Interactive play of OpenRA and of every community app beyond the offscreen QML / CLI / pinned-binary checks.
