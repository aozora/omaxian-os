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
