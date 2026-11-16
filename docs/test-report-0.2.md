# Omaxian OS 0.2 "Space Cat" — build + test report (2026-11-15, CET)

Local build only: nothing uploaded, no apt publish, no push.
Shell: Omaxian v1.1.3 = 2ffd66d8d19d7278f6ef9fc8426fa2e27580c55e (tag verified by scripts/fetch-omaxian.sh).
Base: Devuan 6 Excalibur + backports, fresh mmdebstrap rootfs (no upgrades pending at build time).

## Build history

The first two round-17 builds were lost with the box (box replaced ~11:28; build/, out/ and the
host toolchain were gone). The final build was rebuilt from scratch at 11:35–12:02 with
tools/diag/r17/pipeline.sh (resumable stages, state in `.r17-state`, 8 GiB swapfile, squashfs 4 threads).

Host notes after the box replacement:
- Host apt needs an explicit proxy (transparent egress returns HTTP 500 to apt):
  /etc/apt/apt.conf.d/99r17-egress-proxy -> http://127.0.0.1:8791. The image build uses the existing
  OMAXIAN_BUILD_HTTPS_PROXY (removed from the images at finalize; APT_CONFIG_PASS on every install).
- The round-16 signed CDN prefetch helper was gone, so the full build ran without it (not needed).
- The unchanged packages omaxian-fonts-nerd 3.5.1-1, omaxian-strata 1.2.0-1 and omaxian-ydotool 1.0.4-1
  are byte-identical to the published 0.1 ones: copied from repo-local after gpgv on InRelease and the
  SHA256 in its Packages index. omaxian-voxtype 1.1.1-3 (ISO payload only) was rebuilt.
- A first full build lost Telegram to a Flathub timeout; the pipeline now retries the full rootfs when
  any Flatpak is missing. The final full ISO has all 9 Flatpaks (incl. org.telegram.desktop).

## Artifacts (out/0.2)

| File | Size | SHA-256 |
|---|---|---|
| omaxian-base-0.2-space-cat-amd64.iso | 3065659392 (2.9 GiB) | 45aeaef9ef2884c9932edd8407879786c2910b3ea5576f1a51dbd0e626c2b590 |
| omaxian-full-0.2-space-cat-amd64.iso | 8967221248 (8.4 GiB) | d0437b326d8f484cf4e0745b29d9608adcbdf0eec059d8f74d0551f5f366f5d8 |

Packages: omaxian-base 0.2.0, omaxian-branding 0.3.0, omaxian-calamares-settings 0.3.0,
omaxian-firstboot 0.3.0, omaxian-session 1.1.3-1 (new); fonts-nerd 3.5.1-1, strata 1.2.0-1,
ydotool 1.0.4-1 (unchanged, reused), voxtype 1.1.1-3 (rebuilt). Key upstream: linux-image-amd64
7.2.12-1~bpo13+1, xserver-xlibre 1:7.8+5, quickshell 0.3.0-1~bpo13+1, pipewire 1.6.9-2~bpo13+1,
calamares 3.3.14-1, i3-wm 4.24-1, sysvinit-core 3.14-4devuan1, eudev 3.2.14-4 (1923 packages).

Community apps (all 9, in every user's home): disktree, folio, monologue, omacalc, omacut,
omarchy-meeting-recorder, omawrite, plain, signed.

## VM tests (KVM, 3 GiB / 2 vCPU, no network, one VM at a time; tools/diag/r17)

| VM | Test | Result |
|---|---|---|
| bs | base, UEFI live: versions, no XFCE desktop/Thunar, xfce4-power-manager+xfconf present, 9 apps exec/ldd/desktop + QML offscreen, input group, uinput, ydotoold, quickshell, XDG dirs, DesktopEditors.conf, LCOS rc links, sysctl, keep-manual --check | PASS |
| bs | base, offline UEFI install, File manager page default Strata | PASS ("All done") |
| bs | installed boot -> greeter -> login; check.sh: inode/directory=io.github.lgse.Strata.desktop, /etc/omaxian/file-manager=strata, xdg-mime -> Strata; Super+Shift+F opens Strata; DesktopEditors.conf `[General] titlebar=system` tester:tester 644 (dir 755); calamares removed; kept fdisk/parted/…; dpkg audit clean; GRUB quirks block in grub.cfg | PASS |
| bf | base, UEFI install choosing Folio | PASS: inode/directory=folio.desktop, file-manager=folio, Super+Shift+F opens Folio |
| fs | full, UEFI live + install (Strata, default app groups) + installed checks; 9 Flatpaks, 10 AppImages | PASS |
| ff | full, UEFI live + install choosing Folio + installed checks | PASS: folio.desktop default, Super+Shift+F opens Folio, Telegram present (attempt 1 discarded: test keystrokes landed in Calamares before the terminal opened) |
| bb / fb | base / full, BIOS (SeaBIOS) live + live checks | PASS |

Notes:
- libxfce4ui-2-0 and libxfce4ui-common are installed only as dependencies of xfce4-power-manager
  (the media check flagged them; the check now allows them).
- omaxian-thermald / iio-sensor-proxy / switcheroo-control / bolt and open-vm-tools are linked in
  rc2.d but do not run in QEMU: they are hardware-gated (Intel non-VM, IIO, Thunderbolt, VMware). Boot unaffected.
- The Summary page does not list the chosen file manager (packagechooser legacy method shows no summary line).
- One SeaBIOS live screenshot showed a partially redrawn Calamares window (cosmetic, virtio-vga).

## Not tested
- Real hardware (LCOS services actually starting, GRUB quirk matching a listed model).
- Online paths (firstboot updates, Extra apps downloads), Secure Boot, BIOS *install*.
- Interactive use of every community app beyond offscreen QML load / CLI checks.

## Publish round 17 (2026-11-15, 13:30–13:40 CET)

Approved by the owner (2026-11-15 13:28: upload, apt publish, push). Same method as round 16
(rclone R2 S3, 64M chunks, concurrency 4, size check after upload; harmless R2 `501 NotImplemented`
on first attempts, retries succeeded). Logs: /workspace/publog/r17.

- **ISOs (s3://omaxian-iso/releases/0.2/ → https://download.omaxian.org/releases/0.2/)**, sha256
  streamed over HTTPS (no local re-store), Content-Length = local size, `.sha256` sidecars and
  `SHA256SUMS` identical to local:
  - base: 3065659392 bytes, `45aeaef9ef2884c9932edd8407879786c2910b3ea5576f1a51dbd0e626c2b590` ✔
  - full: 8967221248 bytes, `d0437b326d8f484cf4e0745b29d9608adcbdf0eec059d8f74d0551f5f366f5d8` ✔
- **apt (s3://omaxian-apt ← build/r17/repo):** pool copied (add-only), then dists, then keyring
  (same Cache-Control). Superseded 0.1 pool objects no longer in Packages removed, as in round 16:
  base 0.1.9, branding 0.2.5, calamares-settings 0.2.14, firstboot 0.2.6, session 1.1.0-2.
  fonts-nerd 3.5.1-1 / strata 1.2.0-1 / ydotool 1.0.4-1 are the unchanged 0.1 bytes.
  `rclone check --download`: 0 differences (8 pool + 6 dists).
- **HTTPS (apt.omaxian.org):** InRelease gpgv Good signature (subkey
  `5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75`); Packages sha256 listed in InRelease; all 8 debs'
  streamed sha256 match Packages: base 0.2.0, branding 0.3.0, calamares-settings 0.3.0,
  firstboot 0.3.0, fonts-nerd 3.5.1-1, session 1.1.3-1, strata 1.2.0-1, ydotool 1.0.4-1. Keyring identical.
- **GitHub:** bundle of `main` for branch `omaxian-os-build` (fast-forward from d177fab), pushed via the owner's computer.
- No website change.

---

# Omaxian OS 0.2.1 "Space Cat" — build + test report (round 18, 2026-11-16, CET)

Built and tested locally; published 2026-11-16 20:28–21:05 CET (see "Publish round 18" at the end).
Shell: Omaxian v1.2.2 = b2e551e68dccbc76d6112a6318dffbc23dca1290 (tag verified by
scripts/fetch-omaxian.sh). Every community app's `.omaxian-prebuilt` tree/src= matches its
sources, so the strict build (COMMUNITY_APPS_STALE_OK unset) installed all nine apps from their
sha256-verified pinned binaries; nothing compiled (compilers are blocked on install.sh's PATH).
Base: Devuan 6 Excalibur + backports, fresh mmdebstrap rootfs (stamps removed).

## Build

tools/diag/r18/pipeline.sh, 15:07–15:43 CET, state in `.r18-state`; same limits as round 17
(8 GiB swapfile, squashfs 4 threads / 1G, make -j4, image build through
OMAXIAN_BUILD_HTTPS_PROXY 127.0.0.1:8791, Flatpak retry loop). Rebuilt only omaxian-base,
omaxian-branding and omaxian-session; omaxian-calamares-settings 0.3.0, omaxian-firstboot 0.3.0,
omaxian-fonts-nerd 3.5.1-1, omaxian-strata 1.2.0-1 and omaxian-ydotool 1.0.4-1 are the
published 0.2 bytes (gpgv on build/r17/repo InRelease + SHA256 in its Packages);
omaxian-voxtype 1.1.1-3 (ISO payload only) is the 0.2 build's .deb. Full rootfs: all 9
Flatpaks preinstalled on the first try, 10 AppImages.

## Artifacts (out/0.2.1)

| File | Size | SHA-256 |
|---|---|---|
| omaxian-base-0.2.1-space-cat-amd64.iso | 3065556992 (2.9 GiB) | c39a5e25a3a3d096b77d1fc29b1901b49832325b5002367374d1a5ddbda4ee22 |
| omaxian-full-0.2.1-space-cat-amd64.iso | 8966062080 (8.4 GiB) | 0404e1d251f10af521bf2c78b6f2718be9e5ca22b68c71e453fa8c4ec2f4e543 |

Changed since 0.2: omaxian-base 0.2.0 → 0.2.1 (os-release 0.2.1, OMAXIAN_SHELL v1.2.2),
omaxian-branding 0.3.0 → 0.3.1 (0.2.1 strings), omaxian-session 1.1.3-1 → 1.2.2-1 (v1.2.2,
pinned community-app binaries; + libglib2.0-0t64, libturbojpeg0). All other 1920 of 1923
packages identical to 0.2 (no Devuan update since 2026-11-15): linux-image-amd64
7.2.12-1~bpo13+1 (unchanged), xserver-xlibre 1:7.8+5, quickshell 0.3.0-1~bpo13+1,
pipewire 1.6.9-2~bpo13+1, calamares 3.3.14-1, i3-wm 4.24-1, sysvinit-core 3.14-4devuan1, eudev 3.2.14-4.

## VM tests (3 GiB / 2 vCPU, no network, one VM at a time; tools/diag/r18)

New checks in round 18 (tools/diag/r18/media): `/etc/omaxian-release` OMAXIAN_SHELL="v1.2.2",
os-release VERSION_ID 0.2.1, and PINNED: every `~/.local/bin/<app>` is byte-identical
(sha256) to the binary in its verified pinned tarball; QML launch check also fails on
"non-existent property" / "unavailable" / "failed to load component".

| VM | Accel | Test | Result |
|---|---|---|---|
| bs | KVM | base, UEFI live + offline install (Strata default) + installed checks | PASS: live 75/0, installed 81/0; Super+Shift+F opens Strata |
| bf | KVM, then TCG | base, UEFI live + install choosing Folio; installed checks | PASS: live 75/0 (KVM), install "All done" (KVM); installed boot + checks 81/0 under TCG; file-manager=folio, inode/directory=folio.desktop, Super+Shift+F opens Folio |
| bb | TCG | base, BIOS (SeaBIOS) live + live checks | PASS 75/0 |
| fb | TCG | full, BIOS live + live checks | PASS 75/0 |
| ff | TCG | full, UEFI live + install choosing Folio | live PASS 75/0; File manager page Folio selected; install started and progressing (17% after ~25 min), then stopped: under TCG it needed ~2.5 h more incl. installed checks. Not completed |

Every passing log shows: RELEASE_SHELL (v1.2.2), OS_RELEASE_021, NOXFCE / NOTHUNAR /
XSESSION_NOXFCE (only xfce4-power-manager + xfconf and their libxfce4ui/util deps),
ONLYOFFICE_CONF (`[General] titlebar=system`, owned by the user), PINNED 9/9, QML_PASS for
folio, monologue, omacalc, omacut, omawrite, plain; CLI disktree/signed; DPKG_AUDIT, APT_CONFIG.

### Box KVM fault (host issue, not the ISO)

At 16:31:53 the box's own kernel (6.12.113+) hit `kernel BUG at arch/x86/kvm/x86.c:689`
(`kvm_spurious_fault` from `vmx_write_tsc_offset`) while bf's installed disk was booting, and
killed qemu. Afterwards every KVM guest died the same way within seconds (16:32:21, 16:38:59,
16:46:51; the box kernel is tainted [D]). This is the box's nested virtualization, not the
guest: the same bf disk then booted and passed under TCG. Only a box reboot clears it (not done:
shared machine). The remaining tests ran on TCG (`ACCEL=tcg QCPU=max SLOW=4`, offscreen QML
launch window raised from 12 s to 30 s); the box also showed virtio_balloon "Out of puff"
pressure and wall-clock pauses, so TCG waits ran long.

## Not tested
- **Full ISO install (ff) and its installed checks: not completed (skipped by decision).**
  A KVM retry after the box reboot (19:36 CET) was lost when the box went down again ~19:45
  (likely triggered by KVM guest work; unproven). Marcello chose to skip it and close 0.2.1.
  The Folio install path itself passed on the base ISO (bf), and the full ISO's live checks
  passed under both UEFI (ff) and BIOS (fb).
- Real hardware, Secure Boot, BIOS *install*, online paths (as in 0.2).
- KVM-speed timing of the installed bf boot and the BIOS / ff lives (TCG only).

## Publish round 18 (2026-11-16, 20:28–21:05 CET)

Approved by the owner (2026-11-16 20:27: upload, apt publish, push). Same method as round 17
(rclone R2 S3, 64M chunks, concurrency 4, size check after upload; the usual harmless R2
`501 NotImplemented` on first attempts, retries succeeded). Uploaded from out/0.2.1 (hardlinks of
the safety copy /workspace/iso-keep/0.2.1, sha256 re-verified after both box restarts).
Logs: /workspace/publog/r18.

- **ISOs (s3://omaxian-iso/releases/0.2.1/ → https://download.omaxian.org/releases/0.2.1/)**:
  Content-Length = local size, sha256 of the HTTPS download = local, `.sha256` sidecars and
  `SHA256SUMS` identical to local; `rclone check --download` (ISOs + sidecars): 0 differences (4 matching).
  - base: 3065556992 bytes, `c39a5e25a3a3d096b77d1fc29b1901b49832325b5002367374d1a5ddbda4ee22` ✔
  - full: 8966062080 bytes, `0404e1d251f10af521bf2c78b6f2718be9e5ca22b68c71e453fa8c4ec2f4e543` ✔
    (the first streamed check was cut off by `curl: (56) Connection timed out`, giving a hash of
    a partial body; re-downloaded with resume and re-hashed: match)
- **apt (s3://omaxian-apt ← build/r18pub/repo):** build/ was lost in the box restart, so the repo
  was rebuilt with scripts/make-repo.sh from the 0.2.1 debs (/workspace/iso-keep/0.2.1/debs, the
  ones built for the ISOs; the five unchanged debs are byte-identical to the published pool),
  signed with subkey `5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75`. Pool copied (add-only), then dists,
  then keyring. Superseded pool objects removed afterwards, as in round 17: base 0.2.0,
  branding 0.3.0, session 1.1.3-1. `rclone check --download`: 0 differences (8 pool + 6 dists).
- **HTTPS (apt.omaxian.org):** InRelease GOODSIG/VALIDSIG subkey
  `5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75` with the published keyring (unchanged, identical to
  keys/public); Packages and Packages.gz sha256 match InRelease; all 8 debs' sha256 over HTTPS
  match Packages: base 0.2.1, branding 0.3.1, calamares-settings 0.3.0, firstboot 0.3.0,
  fonts-nerd 3.5.1-1, session 1.2.2-1, strata 1.2.0-1, ydotool 1.0.4-1. Isolated apt root
  `apt-get update` rc=0; candidates base 0.2.1, branding 0.3.1, session 1.2.2-1.
- **GitHub:** bundle of `main` (/workspace/omaxian-os-r18.bundle, d5f5e1d..main) for branch
  `omaxian-os-build`, pushed from the owner's computer.
- No website change.
