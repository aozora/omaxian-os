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
- firstboot optional apps (apt): chromium, gimp, inkscape, krita, podman, distrobox, buildah, docker-compose all `ii`
  at 14:05 CET (shots/d3-fb10.png); the Flatpak ch.protonmail.protonmail-bridge is installed too (d3-fb9.png) — PASS (with the mirror override).
- firstboot.done — **PENDING**: at 14:05 CET firstboot was still installing Flatpak runtimes (d3-fb8.png); there is no
  /var/lib/omaxian/firstboot.done yet. d3 is left running.
- Boot noise: "startpar: service(s) returned failure: smartmontools plymouth" on d3 boot (minor, not investigated).

## d3 summary

| Check | Result |
|---|---|
| Fallback UEFI boot without NVRAM entry | FAIL (grub>); fix in calamares-settings 0.2.3 is not verified (needs an ISO rebuild and re-install) |
| lightdm greeter / first X login | PASS |
| Super+Enter terminal | PASS |
| Keyboard matches installer choice (us) | FAIL: omarchy-keyboard-apply default it,ru phonetic |
| libvirt not enabled when Virtualization is off | PASS |
| hwclock job | PASS (indirect: no installer error; log not kept on the target) |
| firstboot apt optional apps | PASS (mirror override) |
| firstboot.done | PENDING (Flatpak stage running) |

## Round 4 fixes (2026-10-25, 14:10–14:25 CET)

- Keyboard: new `omaxian-seed-keyboard` (omaxian-session 1.0.3-3), run from `Xsession.d/25omaxian-home` right after
  the home seeding. It writes `~/.config/omarchy/keyboard.json` from `/etc/default/keyboard` (layouts, variants, first
  allowed `grp:` toggle; alt_shift_toggle when there are several layouts) only if the file is missing. Unit-tested on the host:
  us -> `[us]`, `it,ru`/`,phonetic` + win_space -> same, `us,de`/`,nodeadkeys` -> alt_shift, empty or invalid layout -> nothing.
  build-packages.sh now keeps our Debian revision for omaxian-session (it used to force `-2`).
- startpar (`smartmontools plymouth` failed) — both come from our image setup:
  - smartmontools: on d3 `smartd` printed "Unable to monitor any SMART enabled devices ... exit status 17" (shots/d3-startpar.png):
    virtio disks have no SMART. build-rootfs sets `smartd_opts="-q nodev0"` (verified: rc 17 -> 0; real SMART disks are still monitored).
  - plymouth: lightdm (S04) quits plymouthd when X starts; then `/etc/init.d/plymouth start` (S18, `set -e`) runs
    `plymouth quit --retain-splash`, which returns 1 with no daemon (reproduced). build-rootfs patches it to quit only if `plymouth --ping`
    answers (patched script: start rc 0 without a daemon). This is an image-time edit of a Devuan conffile, which is kept on upgrades
    (--force-confold).

### Round 4 rebuild (14:10–14:21 CET)
- `omaxian-session 1.0.3-3` built (contains `/usr/bin/omaxian-seed-keyboard` and the new `25omaxian-home`). First attempt failed only because it was started as root (build scripts refuse root), which left a root-owned staging dir. I removed it and rebuilt as the normal user.
- repo-local: `omaxian-calamares-settings 0.2.3` was built twice with identical payloads; only `changelog.gz` (its timestamp) differs. The stale pool copy was removed (`reprepro remove` + `deleteunreferenced`) and re-included from out/debs. Repo now: calamares-settings 0.2.3, session 1.0.3-3.
- From-scratch base rootfs + ISO rebuild started at 14:21 CET.
- 14:49 CET: rootfs + base ISO rebuilt (ROOTFS EXIT 0, ISO EXIT 0, 2.3G, 14:47). Verified in rootfs: `smartd_opts="-q nodev0"`, guarded `plymouth quit` in /etc/init.d/plymouth, `/usr/bin/omaxian-seed-keyboard`, Calamares efi shellprocess runs `calamares-efi-fixup ${ROOT}`.

## i4/d4: fresh UEFI install with the round-4 ISO (from 14:50 CET)
- Live UEFI boot, first try (14:50): **hung on the Plymouth splash.** CD reads stopped at about 334 MB and the guest went idle; Esc and Ctrl+Alt+F2 had no effect. After `system_reset` the second boot reached the i3 desktop in about 4 min (15:06 CET). This is intermittent under TCG; the earlier l3u boot was fine. Watch for it on real hardware.
- Live session (15:08): Super+Enter opens a terminal; `setxkbmap -query` = `us,it` with `grp:alt_shift_toggle`; ~/.config/omarchy/keyboard.json present; `grep -ci startpar /var/log/boot` = 0. Shot: shots/i4-live-term2.png.
- Calamares (15:11–15:15): American English, keyboard English (US)/Default, erase disk (EFI 512M FAT32 + ext4, swap to file), user tester, host omaxian-test. Optional apps: **Thunderbird + Telegram + Virtualization ON**; Chromium, Graphics and Containers OFF (the opposite mix from i3). Welcome page shows "not connected to the Internet" (sandbox proxy). Shots: shots/i4-cala*.png.
- Install 15:16–15:38 CET: **"All done."**, no error dialog (shots/i4-cala18.png). The installer terminal shows the same harmless chcon/.service messages as in i3.
