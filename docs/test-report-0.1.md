# Omaxian OS 0.1 "Trans-Siberian Shaman" — test report (2026-10-25, CET)

ISO: out/omaxian-base-0.1-trans-siberian-shaman-amd64.iso (2.3G, built 12:32 CET, all commits through be8fbfa)

| # | Test | Result | Evidence |
|---|------|--------|----------|
| 1 | d2 (old-ISO install) firstboot: chromium gimp inkscape krita podman distrobox installed, firstboot.done | PASS (with VM apt mirror override, see notes) | shots/disk2-firstboot-verify.png, disk2-firstboot11.png |
| 2 | d2 reboot via UEFI fallback -> greeter | PASS (fallback fixed by hand on d2, old ISO) | shots/disk2-reboot1.png |
| 3 | Calamares fixes in ISO: util-linux-extra (hwclock), calamares-settings 0.2.2, firstboot 0.2.2 | PASS (present in live) | shots/l3u-term.png |
| 4 | Live UEFI boot -> desktop, Super+Enter terminal, setxkbmap us,it, os-release codename | PASS | shots/l3u-now.png, l3u-term.png |
| 5 | Live BIOS boot -> desktop | PASS | shots/l3b-now.png |
| 6 | Fresh Calamares install (UEFI, erase disk, Chromium+Graphics+Containers, Virtualization OFF) | PASS, "All done", no error dialog | shots/i3-cala*.png, i3-cala19.png |
| 7 | d3 (fresh install) UEFI fallback boot with fresh NVRAM | **FAIL**: bare `grub>`; $prefix=(hd0,gpt1)/EFI/debian, ESP has only EFI/omaxian + EFI/BOOT/bootx64.efi | shots/d3-now.png, d3-grub-prompt.png |

Root cause of 7: shellprocess@omaxian-efi ran `/usr/libexec/omaxian/calamares-efi-fixup` *chrooted*, but the
`packages` job had already purged omaxian-calamares-settings (which ships the script) from the target; the `-`
prefix swallowed the error. Fix: calamares-settings 0.2.3 runs the fixup from the live host on `${ROOT}`
(dontChroot: true, no `-`). Needs an ISO rebuild + re-install to verify (not done in this run).
d3 was booted by hand from grub> with `configfile (hd0,gpt1)/EFI/omaxian/grub.cfg` to continue the tests.

## d3 first-login checks (2026-10-25, ~13:40–14:00 CET)

- Console login tester on tty2 works (shots/d3-calalog.png).
- libvirt: no libvirt* links in /etc/rc2.d (Virtualization unselected) — PASS.
- hwclock: the installer log is not persisted to the target (/var/log/installer missing, no Calamares.log), so it can't be grepped; the
  hwclock job finished without an error dialog (i3-cala19.png) — PASS (indirect).
- firstboot: on boot it ran and stalled in apt against https://packages.devuan.org through the sandbox proxy (sandbox artifact, shots/d3-fb1.png).
  Restarted with the mirror override http://10.0.2.2:8099/merged.
- Greeter (lightdm, VT7) up after the manual grub boot; "Test User" preselected (shots/d3-greeter.png) — PASS.
- First X login tester -> Omaxian desktop/bar (shots/d3-x1.png) — PASS.
- Super+Enter opens terminal (shots/d3-x-term.png) — PASS.
- Keyboard — **FAIL**: installer picked English (US) (i3-cala6-keyboard.png) and the system config is right
  (/etc/X11/xorg.conf.d/00-keyboard.conf XkbLayout "us"), but the X session comes up as `it,ru` / `,phonetic` /
  grp:alt_shift_toggle (shots/d3-x-xkb.png, d3-x-kbconf.png). Root cause: vendored
  `~/.local/share/omarchy/bin/omarchy-keyboard-apply` has `DEFAULT_LAYOUT="it,ru"`, `DEFAULT_VARIANT=",phonetic"` and
  uses them when `~/.config/omarchy/keyboard.json` is missing. The live session writes keyboard.json (config/live/37omaxian-live),
  but an installed user gets none. Proposed fix (not done yet): in omaxian-session, seed keyboard.json on first login from
  /etc/default/keyboard (XKBLAYOUT/XKBVARIANT/XKBOPTIONS), or fall back to the system layout instead of it,ru in
  omarchy-keyboard-apply.
