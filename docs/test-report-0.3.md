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
| omaxian-base-0.3-space-cat-amd64.iso | 3610105856 (3.4 GiB) | dd5a0955ef0c64762f45365253c7a7e23203f6be66c31e0a492e2bcd4463af06 |
| omaxian-full-0.3-space-cat-amd64.iso | 9343377408 (8.7 GiB) | 7fb092798cbb2e99e6f696b8d4cf2af35eb8a1be61340d1aa444d2b48118921c |

These hashes are the rebuild that embeds the published archive keyring. The earlier images (base `a65dc356…`, full `682d63d3…`) contained the throwaway test key and are discarded.

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

These four installs were of the first 0.3 images, which still carried the throwaway archive key. The rebuild with the published keyring is in "Archive keyring rebuild" below.

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

## Archive keyring rebuild

`keys/public` is gitignored, so it is not in the `omaxian-os-build` tree. The copy on this machine before the rebuild was the throwaway test key (275 bytes, sha256 `77bace2d6f6b3748aa0e89b733d40a9b1550875dcc91fb0f7151aff97e5d6a74`, fingerprint `45EA168194BBC7F8E2F07F8AC3E85DE24E22ECF6`, uid "DO NOT TRUST"). It differs from the owner's public keyring.

The keyring published with 0.2.1 at https://apt.omaxian.org/omaxian-archive-keyring.pgp is byte-identical to the public keyring supplied for this rebuild: 559 bytes, sha256 `99988abed6c067e96e7fdc10c12a78c59193a8dff75b79bf3638ed5e2f264358`, primary `1D8DE9AD3AFA60790333639EF45C7450C45D49A0`, signing subkey `5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75`.

`omaxian-base` 0.3 was rebuilt with that keyring and installed into both rootfs trees. No file under either rootfs keyring directory contains the test uid. Both squashfs images (LBA 7070) contain `/usr/share/keyrings/omaxian-archive-keyring.pgp` with that sha256. `gpg --show-keys` on the extracted file shows the primary and the signing subkey above, and the file does not contain "DO NOT TRUST". The full squashfs still lists OpenRA `Content/{cnc,d2k,ra}` and `maps/{cnc,d2k,ra}`.

`tests/test-space-cat.sh`: 36 passed, 0 failed.

VM installs of these ISOs (KVM, offline, Strata left as the default):

| VM | Test | Result |
|---|---|---|
| bu | base, UEFI live | PASS (149 checks, 0 FAIL), `KEYRING_SHA_PASS`, `KEYRING_NOT_TEST_PASS` |
| bu | base, UEFI install, then installed boot | PASS (154 checks, 0 FAIL), same keyring checks. The graphical scanout dropped after Strata opened; the checks were completed from tty2. |
| bb | base, BIOS live | PASS (149 checks, 0 FAIL), keyring checks PASS |
| bb | base, BIOS install, then installed boot | PASS (154 checks, 0 FAIL), keyring checks PASS |
| fu / fb | full, UEFI and BIOS | Not completed. After the base installs, KVM hit `kernel BUG at arch/x86/kvm/x86.c` (`kvm_spurious_fault`) while creating a vCPU. A TCG boot of the full ISO reaches the UEFI DVD line and then stays there at 100% CPU, so the full install was not run under TCG. The full image's keyring and OpenRA tree were verified from the squashfs. |

## Unsigned apt repo

`build/r19/repo` stays signed by the throwaway key so a resumed image build can still install packages. It is not the publish tree. `build/r19/repo-unsigned` has the same pool (including rebuilt `omaxian-base_0.3_all.deb`, sha256 `64ebd035039fbc390dcf80dbd0f66a21a86af700d143ad430091915e323222b7`), `dists/excalibur/Release` and the Packages files it hashes, and the real `omaxian-archive-keyring.pgp`. It has no `InRelease` and no `Release.gpg`.

The only file the owner must sign is `dists/excalibur/Release`, with subkey `5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75`:

```sh
gpg --batch --local-user '5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75!' \
  --clearsign --output dists/excalibur/InRelease dists/excalibur/Release
gpg --batch --local-user '5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75!' \
  --detach-sign --output dists/excalibur/Release.gpg dists/excalibur/Release
```

No private key was generated here, and nothing was uploaded.

## Not tested

- Real hardware, Secure Boot, and online first boot (updates, extra-app downloads).
- Interactive play of OpenRA and of every community app beyond the offscreen QML / CLI / pinned-binary checks.
