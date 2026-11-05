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
- d4 (15:39 CET): installed disk only, no ISO, **new OVMF vars** (so no NVRAM entry). The firmware loaded "UEFI Misc Device" (the fallback \EFI\BOOT\BOOTX64.EFI) and went **straight to GRUB → kernel → Plymouth with no grub> prompt** (shots/d4-boot30.png). The UEFI fallback fix (calamares-settings 0.2.3) is verified.
- d4 15:43: LightDM greeter shows "Test User" on host omaxian-test. Login with tester → i3 + bar (bar shows US) at 15:44 (shots/d4-boot-b.png, d4-login.png).
- d4 15:47: Super+Enter opens a terminal. `setxkbmap -query` → **layout us** (no it,ru). ~/.config/omarchy/keyboard.json = `{"layouts":[{"layout":"us","variant":""}],"toggle":""}`, seeded from /etc/default/keyboard (XKBLAYOUT="us"). The keyboard fix is verified (shots/d4-term.png). /var/lib/omaxian at this point: optional-packages.list, optional-pending.list, no firstboot.done yet.

### d4: boot log and firstboot (15:49–15:55 CET)
- `/var/log/boot` is **0 lines**. The `bootlogd` package is in dpkg state `rc` (removed, config left), so nothing writes `/var/log/boot`. The file is an empty image-time leftover (14:47). An empty grep there proves nothing.
- The real boot transcript is `/var/log/boot.log` (2242 bytes, 15:40, written by plymouth). The startpar check was redone against that file (result below).
- At 15:50 firstboot was stuck in `apt-get install thunderbird`: `Could not wait for server fd ... [IP: 198.18.0.1 443]` (the sandbox proxy) for packages.devuan.org.
- **The host mirror override was applied** at about 15:52. The sources were rewritten to `http://10.0.2.2:8099/merged`, the stuck firstboot/apt was killed, and `sudo omaxian-firstboot --now` was re-run. This is a sandbox workaround, not a product fix.
- **startpar check on `/var/log/boot.log`** (needs `grep -a`, the file contains escape codes): the old `smartmontools plymouth` failure is **gone**. One **new** line remains: `startpar: service(s) returned failure: x11-common ... failed!`
  - `/etc/init.d/x11-common` is shipped by `xlibre-x11-common 1:7.8+5`. The Debian `x11-common` is in dpkg state `rc`. The script is a legitimate service, not an orphan; it is S19 in rcS, in parallel with `bootmisc.sh`, `plymouth-log` and others.
  - Run by hand (`sudo sh -x /etc/init.d/x11-common start`) it exits 0, and both `/tmp/.X11-unix` and `/tmp/.ICE-unix` end up 1777 root:root. No "failed to set up" line was logged at boot, so the non-zero exit comes from the `set -e` path during boot, not from the explicit failure branch.
  - Likely cause: a race with `/tmp` cleaning or mounting under startpar. **Not fixed yet.** A reboot is needed to see whether it reproduces. The result is therefore FAIL (new service) for "no startpar failure", even though the round-4 target (smartmontools, plymouth) is fixed.
- Firstboot after the override (16:02): thunderbird and telegram-desktop are done; virt-manager is installing.
- **Optional apps (16:09 CET), all `ii`:** thunderbird 1:140.17.0esr-1~deb13u1, telegram-desktop 5.7.2+ds-2~bpo13+1, qemu-system-x86 1:10.0.13+ds-0+deb13u1, libvirt-daemon-system 11.3.0-3devuan1, virt-manager 1:5.0.0-5+deb13u1, gnome-boxes 48.0-3+b1, spice-client-gtk 0.42-3, bridge-utils 1.7.1-4+b1.
  - `tester` is in `libvirt` and `kvm`.
  - rc2.d has S03virtlogd, S04libvirtd, S05libvirt-guests; `libvirtd` is running.
  - `optional-pending.list` is now empty.
  - Firstboot then moved on to the Flatpak stage (Flathub runtimes plus `ch.protonmail.protonmail-bridge`).
- **firstboot.done** = `2026-10-25T16:12:54+01:00` (16:12 CET). The log ends with "first boot provisioning complete". The AppImage stage downloaded BleachBit 6.0.6, Cursor 3.27.12 and teams-for-linux 2.27.0 inside the guest from upstream; nothing was copied from the host. **Caveat: the apt stage only completed after the host mirror override (see above).**
- 16:15: rebooting d4 once to see whether the x11-common startpar failure reproduces.

### x11-common startpar failure: root cause (16:15–16:35 CET)
- It reproduces on every boot: `/var/log/boot.log` shows one `startpar ... x11-common ... failed!` line per boot (3 boots, 3 lines).
- A boot-time trace (`exec 2>>/var/log/x11c.trace; set -x` added temporarily to the script, since reverted) **never produced a file**, so the script body never ran.
- **Root cause:** `/etc/init.d/x11-common` on the installed system and in `build/rootfs-base` is mode **0644**, with mtime 7 Nov 2025, which is the Debian `x11-common 1:7.7+24+deb13u1` file. `xlibre-x11-common 1:7.8+5` ships it as 0755 (checked with `dpkg-deb -c`). The build installs XLibre by replacing x11-common, which is left in dpkg state `rc`; that conffile takeover kept the old non-executable file. startpar cannot exec it. `sudo sh -x /etc/init.d/x11-common start` by hand works, which is why it looked like a race.
  - Consequence: `/tmp/.ICE-unix` is not created at boot. `.X11-unix` is created by the X server itself, so the desktop still works.
- **Fix (committed, not yet in an ISO):** `scripts/build-rootfs.sh` `s_configure` now does `chmod 0755 /etc/init.d/x11-common` when it is not executable. On existing installs: `sudo chmod 0755 /etc/init.d/x11-common`.
- d4: chmod applied in the guest, then rebooted (16:35) to verify.

## Round 5: ISO rebuild with 215c7a9 (from 18:31 CET)
- Disk space was freed by the user; the d4 disk is gone, so the planned d4 reboot check of the chmod was not done.
- The only change since the 14:47 ISO is `215c7a9`, 7 lines in `s_configure`. No package or Calamares change, so the install path is unchanged since the d4 pass. **No reinstall.**
- Rebuild: removed the `configure` and `finalize` stamps of `build/rootfs-base` (both stages are idempotent), re-ran `build-rootfs.sh base`, then `build-iso.sh base`.
- 18:32 CET: rootfs `configure` + `finalize` re-run (exit 0); `build/rootfs-base/etc/init.d/x11-common` is now 0755. ISO rebuilt (exit 0); the squashfs inside the ISO also has `-rwxr-xr-x /etc/init.d/x11-common`.
- ISO: `out/omaxian-base-0.1-trans-siberian-shaman-amd64.iso`, 2416007168 bytes (2.3 GiB),
  sha256 `b8781ab493119989d2d41a02c56edd25d0024f7ab0da6ea07632ce06a97acbf2` (matches the `.sha256` file).

### Live UEFI boot (OVMF, q35, TCG), 18:34–18:39 CET
- Booted to the desktop (bar, wallpaper) on the first try; no plymouth hang. Super+Enter opened a terminal.
- `ls -l /etc/init.d/x11-common`: `-rwxr-xr-x root root 2762`. **PASS**
- `/var/log/boot.log`: 66 lines; `grep -a -c startpar` = 0; `grep -a -ci failed` = 0. **PASS**
- boot.log contains "Setting up X socket directories... /tmp/.X11-unix /tmp/.ICE-unix."; `/tmp/.ICE-unix` exists (drwxrwxrwt, created 18:34). The x11-common init script now runs at boot.
- Shots: `shots/r5-uefi-1.png`, `r5-uefi-term2.png`, `r5-uefi-term4.png`.

### Live BIOS boot (SeaBIOS, q35, TCG), 18:40–18:43 CET
- Booted to the desktop; Super+Enter terminal OK; x11-common is 0755; `grep -a -c startpar /var/log/boot.log` = 0. **PASS**
- Shots: `shots/r5-bios-1.png`, `r5-bios-term.png`.

### Notes
- The first keystrokes typed into a new terminal before its prompt appears are echoed ahead of the prompt ("ls omaxian@..."). Cosmetic, caused by test typing.
- Cleanup: the VMs were stopped and all OVMF vars copies deleted. No qcow2 disks were created in round 5.

## Round 6 (A): installer locale, English (US) installs Italian formats (19:58 CET)
- Cause: Calamares 3.3.14 `locale` (`Config::setCurrentLocation` → `LocaleConfiguration::fromLanguageAndLocation`) sets LC_NUMERIC/LC_TIME/... from the **time zone's country** unless the user presses "Change..." for the formats. With English (US) and Europe/Rome (our default zone, and the geoip fallback offline), the guess is IT → `it_IT.UTF-8`. `localecfg` writes it to `/etc/default/locale` and `/etc/locale.conf`. LightDM's greeter gets the LC_* via PAM `pam_env` from `/etc/default/locale`. No config key turns this off, and the explicit-choice flag is not exported to global storage.
- Not the cause: `config/debconf/preseed.cfg` (default environment en_US.UTF-8), the image's `/etc/default/locale` (`LANG=en_US.UTF-8` only), `locale.gen` (en_US + it_IT enabled, both stay generated), and live-config. The target is unpacked from the unmodified squashfs, so no live-config locale leftovers reach it.
- Fix (omaxian-calamares-settings 0.2.4): new `/usr/libexec/omaxian/calamares-locale-formats`, called by `calamares-post` (shellprocess@omaxian-post, after `localecfg`). An LC_* value whose country is the time zone's country and which differs from LANG is the automatic guess and is replaced by LANG. Other values, for example an explicit en_GB, are kept. Limitation: explicitly choosing the time zone's own formats while using a different language (English + Italian formats in Rome) is reset to LANG.
- Test: `tests/test-locale-formats.sh` (fake target roots and a settings.conf order check): 8/8 ok. No reinstall, no ISO rebuild for (A). The full ISO of (B) is built from the existing base rootfs (calamares-settings 0.2.3), so it did **not** contain this fix. (Superseded: the round-6 (D) rebuild carries 0.2.6 in both ISOs.)

## Round 6 (B): full offline ISO (from 20:01 CET)
- 20:07 `_staging/.../appimages.tar` appeared on R2 (2458900480 bytes) and was downloaded. It holds **17** AppImages (not 19; `cursor.appimage.zs-old` and `.icons` were excluded at the source). The 17 are exactly one per row of `config/appimages.manifest`, and the extracted sizes total 2458882708 bytes.
- `onlyoffice_desktop_editors.appimage` did not match the manifest glob `*desktopeditors*`. The payload file was renamed to `onlyoffice_desktopeditors.appimage`, which matches the shipped manifest without a package rebuild. The manifest glob is widened to `*desktop*editors*` for the next omaxian-firstboot build.
- `/payload/*.tar` added to .gitignore. The local appimages.tar was deleted after extraction.
- Zoom (`us.zoom.Zoom`, an extra-data flatpak) can't be preinstalled here: apply_extra runs under bwrap and the build host forbids new namespaces. The full stage now installs flatpaks one at a time, warns about the missing ones, and omaxian-firstboot installs them when online. The other 7 flatpaks are preinstalled.
- Optional pool: `apt-get --download-only` was OOM-killed (13 GB RSS) after an https "Ign" on packages.devuan.org. The pool now uses only the build-mirror source list (`Dir::Etc::sourcelist`/`sourceparts=-`) and is cached in build/dl/optional-pool: 328 debs, 550M.
- ISO9660: the full squashfs is 8.9 GB. `-iso-level 3` is required and must come **before** `--` in grub-mkrescue (mkisofs mode). `-compliance iso_9660_level=3` after `--` is applied too late, and xorriso fails with "File exceeds size limit". build-iso.sh now deletes the old ISO first, so a failed run can't report a stale image.

## Round 6 (C): signing-key switch (from 20:30 CET)
- make-repo.sh/reprepro sign with the real subkey `5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75!`. The `!` pins it, and the script dies if the secret subkey is missing. The primary `1D8DE9AD…49A0` is only a stub (`sec#`) in keys/private/gnupg.
- repo-local re-signed: `gpgv --keyring keys/public/omaxian-archive-keyring.pgp` reports "Good signature" for InRelease and Release.gpg. repo-local/omaxian-archive-keyring.pgp equals keys/public.
- Test key `CD76E5317C33069E37DE570B62F519588AAF47F4` deleted (secret and public) from keys/private/gnupg after the switch worked. A test signature afterwards still verifies.
- omaxian-base 0.1.6 ships the real keyring. **ISOs built with omaxian-base ≤ 0.1.5 trust only the test key and can't verify the re-signed repo, so a rebuild is needed** (done below together with the launcher change).
- `DRY_RUN=1 publish-r2.sh apt`: offline plan (no aws CLI here). 6 debs in pool (220M), 6 dists files (44K, +delete remote extras), keyring 4K. No test-key warning. Nothing contacted or uploaded.
- Base rebuild: rerunning apt-setup after finalize had no Devuan source left (finalize empties sources.list). apt-setup now restores the build-mirror sources in that case.

## Round 6 (D): live installer discoverability (from 20:28 CET)
- omaxian-calamares-settings 0.2.5 (live only; the package is purged and calamares-post removes the hooks on installed systems):
  - "Install Omaxian OS" is the first hit for "install" in the launcher (Super+Space). The stock "Install System" entry is hidden for the live user.
  - Super+Shift+I starts the installer.
  - ~/Desktop shortcut.
  - One-time welcome notification (from /etc/X11/Xsession.d/38omaxian-live-installer, gated on boot=live) with an "Install Omaxian OS" action.
- Live UEFI test of the base ISO with 0.2.5: launcher search PASS (shots/r6-base-uefi-search.png), Super+Shift+I PASS, hint files and one-time flag present (r6-base-uefi-term.png). **But** pkexec asked for an admin password (r6-base-uefi-superI.png). live-config only writes a legacy .pkla grant, which polkitd 126 ignores.
- 0.2.6: `/etc/polkit-1/rules.d/49-omaxian-live-installer.rules` returns YES only for `pkexec /usr/bin/env DISPLAY=.. XAUTHORITY=.. calamares`, for the sudo group, while /proc/cmdline has boot=live. calamares-post deletes the rule. tests/test-live-installer-hint.sh: 9/9 ok.

### Build incident (20:38 CET): host /dev wiped on the build box
- `s_full_from_base` ran `rm -rf build/rootfs-full`. The OOM-killed run had left /dev, /proc and /sys mounted inside it, because its cleanup trap never ran. rm went through the /dev bind mount and deleted the box's /dev nodes. It failed on /proc and /sys.
- Recovery: 135 device nodes recreated with mknod from /sys/dev/{char,block}/*/uevent, plus the fd/stdin/stdout/stderr/ptmx symlinks. Nothing else on the host was affected.
- Fix (713f9c5): `rm_rootfs` unmounts first, refuses if any mount is left, and uses `rm -rf --one-file-system`. It is used by bootstrap and full. Tested with a dummy bind mount: the mount was released, the rootfs removed, and the bind source kept.
- Also fixed: helpers clobbered stage()'s `n` through bash dynamic scoping, so the full stamp was written as "17". The variable is renamed. The final du now runs after unmounting.

## Round 6 (E): final verification of the 21:08/21:13 ISOs (from 21:18 CET)
- Staleness check (squashfs extracted): **both** ISOs contain omaxian-base 0.1.6 with the real keyring (= keys/public), omaxian-calamares-settings 0.2.6 and 49-omaxian-live-installer.rules. The full ISO also has payload/appimages (17), payload/openra/Content/{cnc,d2k,ra}, /var/cache/omaxian/optional-pool (Packages + debs incl. grub) and 7 flatpaks (no Zoom, see B). **No rebuild needed.** R2 not touched (staging cleaned up by the owner).
- Base, live UEFI (21:09 boot): i3 desktop at 21:16 (shots/r6d-base-uefi-1.png). **Super+Shift+I opens Calamares with no password prompt** (r6d-base-uefi-superI.png). The 0.2.6 polkit fix is verified.
- Base, live BIOS (21:16 boot): i3 desktop at 21:23 (r6d-base-bios-1/2.png). ~/Desktop/omaxian-install.desktop and ~/.local/state/omaxian/live-installer-hint.done exist. The 60 s login toast was over before the first screenshot (the desktop appears late under TCG). A manual `live-installer-hint notify` (after removing the flag) shows the toast with its Install action (r6d-base-bios-notify.png): **mechanism PASS, login toast itself not captured.**
- Full, live UEFI (21:25 boot, no network): desktop reached (r6d-full-uefi-boot1-3.png). Payload in the live system: 17 AppImages, OpenRA Content cnc/d2k/ra + maps, optional pool 329 entries (328 debs + Packages), 16 flatpak refs (7 apps + runtimes) (r6d-full-uefi-term.png). Super+Shift+I opens Calamares with no password prompt.
- **Test harness limits:** the VM mouse can't be driven (HMP mouse_move is relative and the usb-tablet absolute; PS/2 moves are skewed by acceleration; xdotool clicks in the guest had no effect). Calamares was driven by keyboard only (Alt+N/Alt+I). To get past the partition page without a mouse, the **live overlay only** got `initialPartitioningChoice: erase` in /etc/calamares/modules/partition.conf (package default `none`). This is a test-only change, not a product change.
- Install i6 (full ISO, UEFI, `-nic none`, 64 GiB virtio disk): Location American English (US) + Europe/Rome. Calamares auto-guessed **numbers/dates = italiano (Italia)** and that was left on purpose: this is exactly the locale bug case (shots/i6-loc.png, i6-summary.png). Keyboard Generic 105 / English (US). Erase disk: GPT, EFI 512 MiB FAT32 + 63.5 GiB ext4, swap file (i6-part.png). User tester, host omaxian-i6. Applications: all 6 groups checked (default) (i6-apps.png). Install started 21:45 (i6-inst1.png).
- **Full, live BIOS (21:25 boot, with network): HUNG on the Plymouth splash** (r6d-full-bios-1.png, still there at 21:45, progress bar ~1/3). Same signature as the round-4 UEFI hang: ide2-cd0 rd_bytes stopped at 322 642 596 (kernel 14 MB + initrd 139 MB from GRUB, so about 170 MB of squashfs had been read), idle_time 1209 s (I/O stopped about 1 min into the boot), vCPUs in HLT at a fixed RIP (kernel idle, nothing runnable), Esc / Ctrl+Alt+F2 do nothing. This matches the owner's gnome-boxes report ("first run stopped after boot, 2nd run worked"). Diagnostic boots with a serial kernel console follow.

### Full BIOS splash hang: root cause (21:50–22:00 CET)
- Reproductions: run fb plus diag boots g1 and g3, all via BIOS GRUB with a plain or near-plain command line. Each stopped at the same place (CD reads around 322 MB, splash bar ~1/3, vCPUs in HLT). Boots with a serial kernel console (diag-1, g2) reached the desktop: the extra console output changes the timing, so this is a race.
- A guest memory dump of the hung g3 (HMP dump-guest-memory, then strings) shows the boot is **not** stuck in I/O:
  - runlevel 2 completed. lightdm (pid 2330) and Xorg (pid 2423) are running and plymouthd has exited.
  - Xorg's kernel stack is `vt_waitactive` ← `tty_ioctl` (VT_WAITACTIVE 0x5607) for vt7.
  - lightdm.log: "Using VT 7", then "Waiting for ready signal from X server :0", with no Plymouth handling logged.
- Mechanism: the plymouth initscript (S18, after the lightdm initscript S04) runs `plymouth quit --retain-splash`. If it runs before the lightdm daemon looks for Plymouth, plymouthd exits and leaves tty1 in KD_GRAPHICS mode with VT_AUTO and no owner. The kernel (`change_console`) then silently ignores VT switch requests, so X never gets vt7 and the screen keeps the last splash frame. Esc and Ctrl+Alt+Fn do nothing for the same reason. In the good order, lightdm finds Plymouth on VT1, below its minimum VT 7 ("…so not replacing it"). lightdm then quits Plymouth itself **without** retaining the splash, the console goes back to text mode, and the switch works.
- Fix (9ce9555, scripts/build-rootfs.sh): the initscript patch now produces `if /usr/bin/plymouth --ping; then /usr/bin/plymouth quit || true; fi`, so there is no `--retain-splash`. Both orders end in KD_TEXT. The sed was checked against a reconstructed stock initscript: it produces the line and `sh -n` passes.
- **The 21:08/21:13 ISOs still contain the bug.** A rootfs + ISO rebuild is needed to ship the fix. That is not done here because the brief said to rebuild only if stale.
- Minor, seen in the dump: udevd reports `GOTO 'alsa_restore_std' has no matching label` in 90-alsa-restore.rules (alsa-utils packaging, harmless).

## Round 7: rebuild with the plymouth fix + locale fix (from 22:09 CET)
- Cleanup: every leftover qemu VM killed (dg, the unfinished install i6 on the old ISO, and the hook test VMs hf/hn, which had no result yet). Deleted build/disk-i6.qcow2 (20 GB), its OVMF vars, /tmp/dg3.str and /tmp/fs-full.sq (8.9 GB). Free space went from 36 GB to 64 GB.
- **Locale bug, fixed properly (calamares-settings 0.2.7, 32c7ca0).** The 0.2.4 fix only corrected the target files afterwards, with a time-zone-country rule: the Locale page and the summary still said "numbers and dates: italiano", and an explicit English+Italian-formats choice was lost. Root cause in Calamares 3.3.14 (`LocaleConfiguration::fromLanguageAndLocation`): the automatic formats use an exact language-tag entry if the locale list has one, else the time zone's country (IT → it_IT). Our locale.conf defaults to Europe/Rome, so every English install got it_IT formats.
  - Live only: postinst diverts /usr/share/i18n/SUPPORTED (Calamares' locale list) and adds one bare tag per language (`en UTF-8`, 206 languages). The automatic formats are now the chosen language ("en"). LANG still resolves to en_US.UTF-8 (similarity 100 vs 90 for the bare tag).
  - New job `omaxianlocale`, placed in exec right before localecfg, maps bare tags in global storage `localeConf` to LANG. localecfg then writes /etc/default/locale and runs locale-gen with full names only.
  - A "Change…" choice on the Locale page is always a full name (it_IT.UTF-8, en_GB.UTF-8) and is kept.
  - calamares-locale-formats is now only a safety net (bare tag or empty → LANG). The postrm removes the diversion when calamares-post purges the package, so the installed system gets the stock SUPPORTED back.
  - tests/test-locale-formats.sh: 20/20 ok. It includes a Python port of Calamares 3.3.14's loadLocales + fromLanguageAndLocation, which shows en_US+IT → it_IT with the stock list and → "en" (→ en_US) with ours.
- Plymouth patch made idempotent (cd194b3), so the reused rootfs, already patched with `--retain-splash`, also gets the fix.
- Packages: omaxian-calamares-settings_0.2.7 built, repo-local re-signed (gpgv: Good signature, real subkey).
- Base rootfs rebuild started 22:11 (stamps apt-setup, upgrade, configure, finalize removed; the other stages reused). Full rootfs and both ISOs follow.
- Builds (22:11 to 22:33): base rootfs (stages from apt-setup), base ISO, full rootfs (from scratch on top of base; flatpaks: 8 apps, Zoom still fails extra-data as before → firstboot installs it online; payload 17 AppImages + OpenRA cnc/d2k/ra + maps; optional pool 328 debs) and full ISO, all EXIT 0. Checked in both rootfs: /etc/init.d/plymouth has `plymouth --ping; then /usr/bin/plymouth quit || true; fi` (no --retain-splash), omaxian-calamares-settings 0.2.7, SUPPORTED diversion active, omaxianlocale module present and in exec, omaxian-base 0.1.6, no build-mirror sources left.

### Round 7 live boots (untouched default GRUB entry, no serial console, no network, TCG)
| ISO | Firmware | Boot | Result | Shot |
|---|---|---|---|---|
| base | UEFI | 1 | PASS, desktop in < 2.5 min | shots/r7-base-uefi-1.png |
| base | BIOS | 1 | PASS | shots/r7-base-bios-1.png |
| base | BIOS | 2 | PASS | shots/r7-base-bios-2.png |
| full | BIOS | 1 | PASS (hung 3/3 before the fix) | shots/r7-full-bios-1.png |
| full | BIOS | 2 | PASS | shots/r7-full-bios-2.png |
| full | BIOS | 3 | PASS | shots/r7-full-bios-3.png |
| full | UEFI | 1 (install VM i7) | PASS | shots/i7-01-live.png |

### Round 7 offline install (full ISO, UEFI, `-nic none`, 40 GB virtio disk, keyboard only), started 22:44
- Live tweak (test only, no mouse in the VM): `initialPartitioningChoice: erase` in the live /etc/calamares/modules/partition.conf.
- Live: /usr/share/i18n/SUPPORTED has the bare `en UTF-8` entry (the diversion is active).
- **Location page, time zone Europe/Rome, language American English: "The numbers and dates locale will be set to American English (United States)."** The Summary says the same (shots/i7-05-location.png, i7-11-summary.png). The old ISOs said "italiano (Italia)" here. Locale bug fixed in the UI.
- Users: Tester / tester / tester-standardpc, throwaway password. Applications: all 6 groups checked (offline pool).
- Progress (CET): 22:44 start; 22:56 31% unpacking; 22:59 76% "Install packages" (offline pool); 23:02 78%.
- ISO checksums re-verified with `sha256sum -c` against the build's one-line .sha256 files: both OK.
- 23:09 "All done." (shots/i7-19-progress.png): about 25 min for the offline install. The VM was stopped after Calamares unmounted the target (ACPI powerdown is ignored).
- Installed disk, UEFI via the removable-media fallback (fresh OVMF vars, no NVRAM entry), `-nic none`: GRUB → firstboot init (shots/i7-20-firstboot.png) → greeter; login as tester → desktop at 23:15 (shots/i7-21-login.png); terminal `locale` (shots/i7-22-term.png, saved to ~/r7-locale.txt).
- Offline inspection: the qcow2 was exported read-only with qemu-storage-daemon (FUSE), ext4 root mounted `ro,noload` at its GPT offset.

### Round 7 installed-system results (VM i7, no network at any point)
| Check | Result | Evidence |
|---|---|---|
| Install completes offline (full ISO, all 6 groups) | PASS | i7-19, 25 min |
| Installed disk boots (UEFI fallback) | PASS | i7-20 |
| First login reaches the desktop | PASS | i7-21 |
| LANG/LC_* = en_US.UTF-8 (session `locale`, /etc/default/locale, /etc/locale.conf) | PASS | r7-locale.txt: every LC_* en_US.UTF-8; Europe/Rome time zone kept |
| AppImages in ~/AppImages | PASS | 17/17, all "integrated" in user-firstrun.log |
| OpenRA Content (ra/cnc/d2k) | PASS | 151/115/590 files |
| OpenRA maps | PASS (note) | maps/{ra,cnc,d2k}/release-20250330 seeded; the dirs are empty in payload/ too (stock maps ship inside the AppImages) |
| Flatpaks | PASS | 8 apps, Zoom included |
| Optional apps installed offline from the pool | **FAIL (1 of 23)** | 22 installed (chromium, thunderbird, gimp, inkscape, telegram, podman stack, distrobox, qemu, libvirt, virt-manager, gnome-boxes, ...). **krita missing**, left in optional-pending.list |
| /var/lib/omaxian/firstboot.done without network | **FAIL** | not written: krita pending, and by design firstboot exits "offline: will retry at next boot" when nothing is reachable |
| Live-only packages purged (live-boot/-config/-tools, calamares, omaxian-calamares-settings), pool sources and pool removed | PASS | dpkg status, sources.list.d |
| omaxian-base 0.1.6, plymouth initscript without --retain-splash | PASS | |
| Stock /usr/share/i18n/SUPPORTED restored | **FAIL** | file missing on the target |

### Root causes and fixes (source only; not in the round-7 ISOs)
- **krita**: Calamares' apt `remove` operation is followed by `apt-get --purge autoremove`, which ran before the netinstall installs (history.log). It purged libxcb-res0 and libqt6core5compat6, which only Calamares had pulled in. The pool skips packages already in the rootfs, so they were not there and apt refused krita ("libkf5windowsystem5 Depends libxcb-res0 … not installable", reproduced offline on an overlay of the installed root). Fix: `s_optional_pool` now also downloads every group dependency that the live-package purge plus autoremove would remove. Computed on rootfs-full: libkf6guiaddons-bin libqt6core5compat6 libxcb-res0.
- **SUPPORTED**: apt purge runs postrm twice (`remove`, then `purge`). The second `rm -f` deleted the stock file that the first run had just restored. Reproduced with tests/test-supported-diversion.sh (real dpkg-divert --root). Fix: omaxian-calamares-settings 0.2.8 postrm only acts while the diversion still belongs to the package. The test now passes. Impact on round-7 installs: `dpkg-reconfigure locales` has no list. Workaround: `apt-get install --reinstall locales`.
- **firstboot.done offline**: unchanged (design decision needed). firstboot also refreshes Flatpaks/AppImages online, so it never marks done without network. Proposal: on the full ISO, when nothing is pending and all Flatpaks are present, write firstboot.done offline and leave updates to the normal updater.
- Both fixes need a rebuild (calamares-settings 0.2.8 + full rootfs pool) to reach the ISOs.

## Round 8 (Mon 26 Oct 2026, CET): full-ISO offline firstboot, rebuild with all fixes

Decision (owner, 05:49): on the FULL ISO, omaxian-firstboot writes firstboot.done offline when nothing is pending; the BASE ISO keeps retrying until online.

- 06:00 omaxian-firstboot 0.2.3 (commit 7ad0b9e): `full_offline_complete()` (marker /var/lib/omaxian/full-offline, set by the full build; no pending apt; all wanted Flatpaks present; every AppImage manifest row is cached or in the payload). New tests/test-firstboot-offline.sh: 10/10 pass.
- build-rootfs.sh: Flatpak install for the full rootfs runs under bwrap-as-root (`BW`), so Zoom's extra-data apply_extra works (the kernel refuses userns inside a chroot).
- tests/test-locale-formats.sh fixture fix (bfba2ed): "stock" now means rootfs-base's SUPPORTED.omaxian-orig; the box has no SUPPORTED and the diverted file has bare tags. 20/20 pass.
- Root-owned build/pkg/omaxian-branding and build/pkg/omaxian-firstboot fixed with chown; `build-packages.sh` (all) passes. omaxian-session isn't byte-reproducible at the same version, so the repo copy was kept and make-repo passes.
- Builds (05:55 to 06:04, all EXIT 0; mirror via tools/devuan-redirect-proxy.py): base rootfs (stamps apt-setup/upgrade/configure/finalize removed, omaxian-calamares-settings 0.2.7→0.2.8 and omaxian-firstboot 0.2.2→0.2.3 upgraded), base ISO, full rootfs from base, full ISO. Full rootfs: **all 8 Flatpaks installed incl. us.zoom.Zoom** (bwrap-as-root fix), marker /var/lib/omaxian/full-offline present, optional pool 419 debs / 641M incl. krita, libqt6core5compat6, libxcb-res0 (the live-only dependency computation now adds 91 packages, a safe superset).
- ISOs: base 2416023552 B sha256 9907ec4d735ee797ec8c8d3115d62e5e2ef345bb29e40e5521694d8b46d67937; full 9561276416 B sha256 ba99bff40a0e7676a7a06013d2f6ac77cfc2b98f805855cd5da4089708302389. `cd out && sha256sum -c` OK for both.

### Round 8 live boots (untouched default GRUB entry, no serial, `-nic none`, TCG)
| ISO | Firmware | Result | Shot |
|---|---|---|---|
| base | UEFI | PASS, desktop 06:02 (boot 05:59) | shots/l8bu-1.png |
| base | BIOS | PASS, desktop 06:11 | shots/l8bb-1.png |
| full | UEFI | PASS, desktop 06:11 | shots/l8fu-1.png |
| full | BIOS | PASS, desktop 06:14 | shots/l8fb-1.png |
| full | UEFI | PASS (install VM i8) | shots/i8-01-live.png |

### ACPI shutdown (QEMU system_powerdown), base live UEFI
- Default: ignored (VM still running after 30 s).
- Diagnosis in the live session (shots/l8bu-3.png): the kernel "Power Button" input device exists and elogind handles it by default (HandlePowerKey=poweroff), but **xfce4-power-manager** (autostarted by i3_autostart) holds a *block* inhibitor on `handle-power-key` and its `power-button-action` is **3 = Ask**, from /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml. Ask needs an xfce4-session manager, which i3 doesn't run, so the press does nothing.
- Confirmed: after `xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/power-button-action -s 4` (shutdown), system_powerdown shut the live system down (live-boot's "remove the live-medium … press ENTER" prompt, shots/l8bu-4.png), and the VM powered off 10 s after Enter.
- Proposed fix (not in these ISOs): set power-button-action to 4 in i3_autostart's xfpm defaults block (or ship the xfconf default as 4).

### Round 8 offline install (full ISO, UEFI, `-nic none`, 40 GB virtio, keyboard only), VM i8
- Same live tweak as round 7 (erase default in partition.conf). Live SUPPORTED diversion active (bare `en UTF-8` present).
- Location: Europe/Rome; "system language … American English (United States)", "numbers and dates locale … American English (United States)" (shots/i8-04-location.png, i8-10-summary.png).
- Users: Tester / tester / tester-standardpc, throwaway password. Applications: all 6 groups checked (shots/i8-09-apps.png).
- 06:21 install started.
- 06:40 78% "Install packages" (offline pool).
- 06:49 "All done." (shots/i8-18-progress.png), 28 min. VM stopped; installed disk booted UEFI (fresh vars, fallback loader), `-nic none`.
- 06:51 LightDM greeter (Tester preselected); 06:54 i3 + Quickshell desktop (shots/i8-19-boot.png, i8-20-desktop.png).
- 06:54 `locale` in terminal: all en_US.UTF-8 (shots/i8-21-locale.png); ~/AppImages = 17 (i8-22-state.png). Clean `sudo poweroff` 06:59.
- Offline inspection of the installed disk (read-only qemu-storage-daemon export, tools/diag/inspect.sh check):

| Check (installed disk, i8, full ISO, offline) | Result |
|---|---|
| Optional apps 23/23 incl. krita 1:5.2.9, chromium 156, thunderbird 153.5esr; optional-pending.list empty | PASS |
| /usr/share/i18n/SUPPORTED present, md5 = stock (646522ed…), no diversion left | PASS |
| firstboot.done written offline 06:50:19; log "full ISO: everything installed offline, first boot provisioning complete" | PASS |
| Locale: /etc/default/locale, /etc/locale.conf and session `locale` all en_US.UTF-8; timezone Europe/Rome | PASS |
| AppImages: 17 in ~/AppImages, integrated by user firstrun | PASS |
| OpenRA Content ra/cnc/d2k = 151/115/590 files + release-20250330 maps | PASS |
| Flatpaks 8 incl. us.zoom.Zoom (deployed) | PASS |
| Live packages purged; optional pool removed; sources = devuan, omaxian, xlibre, extrepo brave/librewolf | PASS |
| Boot to greeter/desktop UEFI with no network | PASS |

Round 8 verdict: all checks PASS. Open issues: ACPI power button (xfpm action "Ask" under i3; proposed fix power-button-action=4, not in these ISOs); omaxian-session not byte-reproducible at the same version; stale out/omaxian-base-0.1.0-dev-amd64.iso.sha256; optional-pool extra-deps list (91) is a superset; out/*.sha256 and build stamps root-owned; cosmetic: bwrap trigger messages in flatpak install, udev alsa GOTO warning, changelog dates. Test scripts saved to tools/diag/.

## Round 10 (Mon 26 Oct 2026, CET): VoxType option B (7th optional group, full ISO only), rebuild both ISOs
- Build chain tools/diag/r10-chain.sh: base rootfs 12:12, base ISO 12:13, full rootfs 12:16, full ISO 12:19 (ALLDONE 12:19:35).
- Full build log: `voxtype_1.1.1-1_amd64.deb sha256 OK (1d4767ca…57ed3c), signature OK (9CCF7915B750CAE8B095ED1AA3FC9F33FD209279), binaries match signed SHA256SUMS.txt`; `optional pool: offline resolve OK (330 to install)`; `optional pool: 421 debs, 1000M`.

| ISO | Size (bytes) | sha256 |
|---|---|---|
| out/omaxian-base-0.1-trans-siberian-shaman-amd64.iso | 2,461,612,032 | f1f330229736db43e58a6117590ac2c054331acd86e15923bd35c365f3ede0f0 |
| out/omaxian-full-0.1-trans-siberian-shaman-amd64.iso | 9,939,206,144 | 7236036c36527c7ef986820cc64832627c6315f0e1e963ce8540c9faa9d25fc4 |

The .sha256 files next to them are written by the build and checked against an independent sha256sum (match). The stale out/omaxian-base-0.1.0-dev-amd64.iso.sha256 has been removed.

### Round 10 live boots (untouched default GRUB entry, `-nic none`, TCG)
| Boot | Desktop | fc-match monospace | power-button-action / xfpm | netinstall groups | ACPI system_powerdown |
|---|---|---|---|---|---|
| base UEFI (lbu) | PASS 12:20 | JetBrainsMono Nerd Font Mono | 4 / running | 6, no offline-only list | PASS (shutdown → live-boot eject prompt → Enter → VM off) |
| base BIOS (lbb) | PASS 12:25 | JetBrainsMono Nerd Font Mono | 4 / running | 6, no offline-only list, no voxtype pkg | PASS (same) |
| full UEFI (i10 live) | PASS 12:25 | JetBrainsMono Nerd Font Mono | 4 / running | 7, VoxType `selected: false`, offline-only = voxtype omaxian-voxtype, both debs in pool | (the installed system was tested instead) |
| full BIOS (lfb) | PASS 12:31 | JetBrainsMono Nerd Font Mono | 4 / running | 7, VoxType `selected: false` | PASS (same) |

### Round 10 offline install (full ISO, UEFI, `-nic none`, 40 GB virtio, keyboard only), VM i10
- Same live tweak as rounds 7/8 (test only): partition.conf erase default. Location Europe/Rome, American English for both language and formats (shots/i10-04-location.png, i10-10-summary.png).
- Users: Tester / tester / tester-standardpc, throwaway password. Applications: VoxType unchecked by default (shots/i10-09-apps.png), checked by keyboard, so all 7 groups are checked (i10-09b-apps.png).
- 12:29:29 install started. 12:47 at 76% "Install packages" (offline pool).
- ~13:07 "All done." (shots/i10-21.png), ~36 min. The offline package stage stayed at 78% for ~15 min because the voxtype deb (375 MB) unpacks slowly under TCG.

### Round 10: installed system (i10), checks in the session (13:12–13:16 CET)
- Disk boots UEFI offline to the LightDM greeter, and Tester logs in to i3: PASS.
- `fc-match monospace` gives `JetBrainsMonoNerdFontMono-Regular.ttf: "JetBrainsMono Nerd Font Mono"`: PASS. `ls ~/AppImages | grep -ic appimage` gives 17: PASS. xfconf power-button-action is 4: PASS.
- ACPI `system_powerdown` on the installed system powers the VM off in about 10 s: PASS.
- `voxtype --version` under the default QEMU CPU (qemu64, x86-64-v1) **failed with SIGILL**. Upstream's "baseline" binary needs x86-64-v2.
  Fix: the wrapper now refuses cleanly with exit 132 and a message on pre-v2 CPUs (omaxian-voxtype 1.1.1-2), and there is a new test in tests/test-voxtype.sh (25/25 pass). docs/voxtype.md lists it as a known limit.
  The full ISO is being rebuilt with 1.1.1-2 (tools/diag/r10b-full.sh); the base ISO is not affected.
  To re-verify, the installed disk was rebooted with `-cpu max` (new `CPU=` option in installvm.sh).
- With `-cpu max` (TCG, avx2+fma+sse4_2), `voxtype --version` in the session prints `voxtype 1.1.1` (wrapper → avx2 variant): **PASS** (shots/i10-31-vx.png). ACPI powerdown works again: off in about 12 s.

### Round 10: offline inspection of the installed disk (13:22 CET, tools/diag/inspect.sh, read-only)
| Check | Result |
|---|---|
| Optional packages (7 groups, 25 packages incl. voxtype + omaxian-voxtype) | 25/25 installed, optional-pending.list empty: PASS |
| firstboot.done without network | created 13:10:50: "full ISO: everything installed offline, first boot provisioning complete": PASS |
| Locale / timezone | en_US.UTF-8 everywhere, Europe/Rome; SUPPORTED not diverted, matches original: PASS |
| AppImages | 17: PASS |
| OpenRA | ra/cnc/d2k content 151/115/590, maps for ra/cnc/d2k release-20250330: PASS |
| Flatpaks | 8, including us.zoom.Zoom: PASS |
| Live packages purged, optional pool removed | PASS |
| VoxType | diversion /usr/bin/voxtype → voxtype.upstream by omaxian-voxtype; voxtype 1.1.1-1 + omaxian-voxtype 1.1.1-1 (built before the guard); `voxtype --version` in a chroot on the AVX2 host: 1.1.1: PASS |
| No silent input group | `id tester`: not in `input`: PASS |
| i3 keybinding | ~/.config/i3/config.d/60-voxtype.conf seeded: `bindsym Mod4+Ctrl+v exec --no-startup-id /usr/bin/omaxian-voxtype-toggle`: PASS |
| Fonts / power | fc-match monospace → JetBrainsMono Nerd Font Mono; power-button-action is 3 (package default) in /etc/xdg and 4 per user (seeded only if unset, as in round 9): PASS |

inspect.sh fix: a stale FUSE export (`Transport endpoint is not connected`) stopped `umount` from removing build/i10.raw. umount now checks /proc/mounts.

### Round 10b: final full ISO (13:25 CET, omaxian-voxtype 1.1.1-2)
- Rebuild: tools/diag/r10b-full.sh. Only the `full` stage and the full ISO were rebuilt (rootfs 13:19–13:22, ISO 13:22–13:25). The base rootfs (stamps 12:12) and the base ISO (12:13) are untouched.
- The base ISO doesn't need a rebuild: omaxian-base.packages has no voxtype at all. omaxian-voxtype exists only in the full ISO's optional pool, and the base ISO has no pool.
- Changes beyond voxtype 1.1.1-2: none found.
  - The full dpkg set and versions are identical to base (the full rootfs is a copy of base).
  - Flatpaks: the same 8 apps; Zoom has the same commit, 1323ee65…319c, as the installed i10 system. The other 7 Flatpak commits weren't compared because the i10 disk was already deleted.
  - 17 AppImages.
  - The pool is again 421 debs / 1000M with 330 resolving offline, and voxtype_1.1.1-1 has the same sha256 and signature (OK).
  - So the full install was not redone.
- Guard check: omaxian-voxtype_1.1.1-2 taken from the rebuilt pool, run with x86-64-v1 cpuinfo, gives the message and exit 132: PASS.

| Live boot of final full ISO (`-nic none`, TCG) | Desktop | fc-match monospace | power-button-action | netinstall groups | pool voxtype | ACPI system_powerdown |
|---|---|---|---|---|---|---|
| UEFI (lfu) | PASS | JetBrainsMono Nerd Font Mono | 4 | 7 | omaxian-voxtype_1.1.1-2 + voxtype_1.1.1-1 | live-boot prompt, Enter → off: PASS |
| BIOS (lfb) | PASS | JetBrainsMono Nerd Font Mono | 4 | 7 | omaxian-voxtype_1.1.1-2 + voxtype_1.1.1-1 | live-boot prompt, Enter → off: PASS |

Final ISOs (`sha256sum -c` on both .sha256 files: OK):

| ISO | Size (bytes) | sha256 |
|---|---|---|
| out/omaxian-base-0.1-trans-siberian-shaman-amd64.iso (12:13) | 2,461,612,032 | f1f330229736db43e58a6117590ac2c054331acd86e15923bd35c365f3ede0f0 |
| out/omaxian-full-0.1-trans-siberian-shaman-amd64.iso (13:25) | 9,939,206,144 | aa8b3f46c1b95d667bdf17ffefecc57b949430c03c00ca70b564baafd8cf29ea |

The 12:19 full ISO (7236036c…) has been replaced. The round 10 install results above were taken from it; the only difference is the voxtype wrapper.

Round 10 verdict: all checks PASS. `voxtype --version` passes on an x86-64-v2+ CPU, and pre-v2 CPUs now get a clean refusal instead of SIGILL.
Test disks and VM files deleted. Nothing uploaded, R2 not touched.

Open issues:
- The VoxType signing key is trust-on-first-use.
- A speech model needs internet on first use.
- The VoxType daemon isn't stopped at logout.
- VoxType needs x86-64-v2.
- Per-user fonts are duplicated.
- Greeter font.
- omaxian-branding/omaxian-session are not byte-reproducible.
- Online installs may pull in wtype/wl-clipboard.
- An offline full install takes about 36 min under TCG.
- Also removed a stale round-8 FUSE export, build/i8.raw (no daemon behind it).

## Publish (2026-10-26, ~20:00 CET)

- ISOs uploaded to R2 `omaxian-iso/releases/0.1/` (base overwritten):
  - base: 2,461,612,032 B, sha256 f1f33022…e0f0 — verified by full HTTPS download from download.omaxian.org.
  - full: 9,939,206,144 B, sha256 aa8b3f46…29ea — verified by full stream hash from R2 + HTTPS Content-Length.
  - both `.sha256` files fetched over HTTPS and byte-identical to local.
- apt repo NOT published: R2 token gets 403 AccessDenied on bucket `omaxian-apt` (list and put). Nothing written there. **Update (2026-10-26 20:26 CET):** published after the token was updated; see Round 11.

## Round 11: omaxian-base 0.1.7, apt.omaxian.org enabled by default (2026-10-26, started 20:47 CET)

- The apt repo was published at 20:26 CET and verified over HTTPS: InRelease GOODSIG/VALIDSIG 5CD4C2DB…, Packages sha256 OK, isolated apt-get update/download OK.
- omaxian-base 0.1.7: `omaxian.sources` ships `Enabled: yes`. The preinst normalises a 0.1.6 file whose only change is `Enabled: yes` (dpkg's recorded md5 of the file with yes→no), so dpkg upgrades without a conffile prompt. Other local edits get standard dpkg conffile handling.
- build-rootfs.sh: during the build `omaxian.sources` is dpkg-diverted (`--local`) to `/etc/apt/omaxian.sources.omaxian-build` (from s_apt_setup); s_finalize removes the diversion and checks the file. Build-time apt therefore only uses the local repo and the build mirror. The full-ISO pool steps already used `sourceparts=-`.
- Tests: new tests/test-omaxian-sources-upgrade.sh (real dpkg, overlay on rootfs-base): 7/7 pass (pristine, sed-enabled, customised enabled/disabled, no-policy, build diversion, admin-disabled reinstall). test-firstboot-offline.sh case 12 (apt-get update fails → firstboot continues): 12/12 pass. Other tests pass.
- repo-local regenerated (make-repo.sh) with omaxian-base 0.1.7, signed by 5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75 (gpg VALIDSIG). The other 6 debs are byte-identical to the published pool.
- First 0.1.7 build (20:47–20:55 CET) all OK; base UEFI live boot: `Enabled: yes`, offline `apt-get update` only warns ("Some index files failed to download", no hang). Those ISOs were superseded by Round 11b before the BIOS boots finished.

## Round 11b: Strata 1.1.1, Omaxian shell v1.0.4, Telegram as a Flatpak (2026-10-26, 20:58–… CET)

Folded in before the final ISO builds (the Round 11 ISOs were rebuilt).

- **Strata 1.1.1** (`STRATA_VERSION`, omaxian-strata 1.1.1-1): GitHub release v1.1.1 (not a prerelease). The manifest's Ed25519 signature verifies against the unchanged pinned key (install.sh / data/update-keys.json). Archive `strata-1.1.1-x86_64.tar.gz` sha256 e0552e0772fcded13a82884747b28f0b32220a32931cda6e55f83575bbe50734 matches the signed manifest. The manifest's `source_commit` is fb031552…; the tag v1.1.1 points to be3343a5… Same file list and .desktop file as 1.1.0. build-packages.sh now refuses a changelog/STRATA_VERSION mismatch.
- **Omaxian shell v1.0.4** (`OMAXIAN_SHELL_REF`, omaxian-session 1.0.4-1, upstream version still from the shell's `version` file). The Omarchy ref follows setup.sh `UPSTREAM_REF` = v4.0.6 (unchanged). Upstream changes in our vendored parts:
  - keyboard default `us` (was it,ru);
  - deploy.sh seeds `~/.config/omarchy/keyboard.json` from /etc/default/keyboard;
  - new theme transiberian;
  - power button: i3_autostart / omarchy-idle-lock-apply map xfpm `power-button-action` unset/3 to 4 (Shutdown). Our Xsession.d/36omaxian-xfpm default agrees and stays as the early login-time default.
- Build fix: gen-home-template.sh drops the `keyboard.json` that v1.0.4's deploy.sh renders from the *build host's* keyboard. In /etc/skel it would shadow the installer's layout, because omaxian-seed-keyboard never overwrites. The fix also drops render leftovers (`__pycache__`, `shell.json.bak`). The fastfetch patch applies as before. omaxian-base 0.1.7's /etc/omaxian-release records `OMAXIAN_SHELL="v1.0.4"`. 0.1.7 was never published, so its repo-local copy was replaced.
- **Telegram:** a Flatpak (`org.telegram.desktop`) instead of the `telegram-desktop` apt package.
  - `config/optional-groups.list` gets an optional 6th field (the group's Flatpaks); the Telegram group has no apt packages.
  - The Calamares "Telegram" group stays (preselected). Its only netinstall entry is `flatpak`, which is always installed (an apt no-op that works offline), with the post-install step `omaxian-optional-flatpak select org.telegram.desktop`. That step records the pick in /var/lib/omaxian/optional-flatpaks.list. omaxianoptional (omaxian-calamares-settings 0.2.10) does not count it as a package and creates the file even when it is empty.
  - omaxian-firstboot 0.2.4 installs picked optional Flatpaks from Flathub when online (base ISO).
  - Full ISO: like the other Flatpaks, Telegram is preinstalled system-wide in the image. Firstboot removes it offline (plus unused runtimes) when the group was not picked, and the offline-done check requires it only when picked.
  - Choice: preinstall plus offline removal rather than a local flatpak repo or bundle. It is simpler, needs no extra ISO payload and works fully offline. If the preinstall failed at build time, firstboot installs it online.
  - Optional apt packages: 24 (was 25).
- Tests: test-firstboot-offline.sh 18/18 (new 13–18 Telegram picked/unpicked/missing, base online install/skip, no-record default); new tests/test-optional-flatpaks.sh 11/11; test-omaxian-sources-upgrade.sh 7/7; voxtype 25/25; the others pass.
- Packages: omaxian-base 0.1.7, omaxian-strata 1.1.1-1, omaxian-session 1.0.4-1, omaxian-firstboot 0.2.4, omaxian-calamares-settings 0.2.10 (branding 0.2.5, fonts-nerd 3.5.1-1 unchanged, byte-identical). repo-local regenerated and signed by subkey 5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75 (VALIDSIG). Nothing published.

### Round 11b/11c/11d builds (21:12–21:28 CET)
- r11b (21:12) was stopped during the full stage. The base rootfs still had the *first* omaxian-base 0.1.7 build (`OMAXIAN_SHELL="v1.0.3"`), because dist-upgrade skips a rebuilt package whose version did not change. **Build fix:** s_upgrade now always runs `apt-get install --reinstall` on the installed omaxian-* packages from repo-local ("7 reinstalled"). r11c base: /etc/omaxian-release and /etc/issue.omaxian say v1.0.4, `:: omaxian.sources: Enabled: yes`, netinstall.conf has the Telegram `flatpak` + post-install entry, and the home template has no keyboard.json.
- r11c full: the optional pool still held telegram-desktop and its dependencies (421 debs, 1000M). The reused download cache (build/dl/optional-pool) is copied in wholesale. **Build fix:** after the offline resolve check, s_optional_pool now deletes pool debs that are not in the resolver's Inst set, the live-only dependencies or the local VoxType debs. It then re-indexes and re-runs the offline resolve check. r11d (full only, 21:22–21:28): "dropped 8 unused debs", offline resolve OK after pruning (322 to install, was 330 with telegram-desktop), **413 debs, 963M**, no telegram deb. org.telegram.desktop (7.3.3) preinstalled with the other 8 Flatpaks (9 apps).
- ISOs: base 2,467,051,520 B (21:18), full 10,207,485,952 B (21:28). The full ISO is ~268 MB bigger than r11 because of the Telegram Flatpak plus runtime, partly offset by the smaller pool. `sha256sum -c` OK for both .sha256 files.

### Round 11c/11d live boots (TCG, `-nic none`, default GRUB entry)
| ISO / firmware | desktop | omaxian.sources | /etc/omaxian-release | other |
|---|---|---|---|---|
| base UEFI (lbu) | PASS 21:25 (shots/r11c-lbu-1.png) | Enabled: yes | v1.0.4 | offline `apt-get update` rc=0, only "W: … failed to download" (r11c-lbu-3.png); ~/.config/omarchy/keyboard.json seeded at login |
| base BIOS (lbb) | PASS 21:25 (r11c-lbb-1.png) | Enabled: yes, apt.omaxian.org queried and fails resolving, rc=0 (r11c-lbb-2.png) | v1.0.4 | live layout us,it (LIVE_KEYBOARD_LAYOUTS, intended) (r11c-lbb-3.png) |
| full UEFI (lfu) | PASS 21:32 (r11c-lfu-2.png) | Enabled: yes | v1.0.4 | 9 Flatpak apps incl. org.telegram.desktop, pool 413 debs, 0 telegram debs, strata 1.1.1 (r11c-lfu-3.png) |
| full BIOS (lfb) | PASS 21:38 (r11c-lfb-1.png) | Enabled: yes | v1.0.4 | 9 apps, Telegram 7.3.3, pool 413, strata 1.1.1, offline `apt-get update` rc=0 (r11c-lfb-2.png) |

### Round 11 offline install i11 (full ISO, UEFI, `-nic none`, 40 GB virtio, keyboard only)
- Same test-only live tweak (partition.conf erase default). Europe/Rome, American English for language and formats, keyboard English (US) (shots/i11-05…i11-10). User Tester / tester, throwaway password.
- Applications: default selection, 6 groups checked including Telegram (Flatpak), VoxType unchecked (i11-09-apps.png). Install started 21:39:35.

## Round 12 (0.1.7 + OpenSpot removed, 6 optional "extra apps" AppImages)
- i11 was stopped at about 23% (superseded by the new AppImage requirement). Its disk was deleted.
- Code: config/appimages.manifest now has 10 bundled + 6 optional rows (column 5 `optional`, column 6 sha256, column 7 label), and OpenSpot is gone. The payload file was moved to build/payload-removed/, not deleted. New omaxian-optional-appimage records picks in /var/lib/omaxian/optional-appimages.list. omaxian-appimage-fetch downloads only the picked optional rows and verifies the sha256. firstboot treats a picked, not-yet-downloaded extra app as pending on the full ISO, so firstboot.done is not written offline. gen-netinstall `--appimages` adds the "Extra apps (downloaded after install)" group with one unselected subgroup (checkbox) per optional app. omaxianoptional ignores these entries.
- Packages: omaxian-firstboot 0.2.5 and omaxian-calamares-settings 0.2.11. repo-local was re-exported; the InRelease signature from subkey 5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75 checks out with gpgv. Nothing was published.
- Tests: test-firstboot-offline.sh 22/22 (new cases 19–22: extra app not picked → done; picked and offline → pending, not done; picked and cached → done; a payload copy is ignored). New tests/test-optional-appimages.sh 16/16. test-optional-flatpaks 11/11, voxtype 25/25, and the others pass.
- r12 build (tools/diag/r12-chain.sh, 22:06–22:21 CET): the full rootfs log says "payload: 10 bundled AppImages (1.1G)".
  - base ISO 2,467,051,520 B (22:08).
  - full ISO 8,874,823,680 B (22:20), 1.33 GB smaller than r11d.
  - `sha256sum -c` OK for both.
- Static check (unsquashfs, both ISOs):
  - Both: omaxian-base 0.1.7, firstboot 0.2.5, calamares-settings 0.2.11, session 1.0.4-1, strata 1.1.1-1, no telegram-desktop deb, omaxian.sources `Enabled: yes`, 6 `omaxian-optional-appimage select` entries, no OpenSpot in the manifest.
  - Base netinstall: 7 groups; payload absent.
  - Full netinstall: 8 groups; payload has exactly the 10 bundled AppImages; org.telegram.desktop preinstalled.

### Round 12 live boots (TCG, `-nic none`, default GRUB entry)
| ISO / firmware | result |
|---|---|
| base UEFI (lbu) | PASS 22:33 (shots/r12-lbu-2.png). In the session: base 0.1.7, calamares-settings 0.2.11, firstboot 0.2.5, session 1.0.4-1, strata 1.1.1-1, Enabled: yes, 6 extra-app entries. Offline `apt-get update` only prints W: lines, rc=0 (r12-lbu-3.png) |
| base BIOS (lbb) | PASS 22:43 (r12-lbb-2.png). Same versions, Enabled: yes, 6 entries, `/sys/firmware/efi` absent = BIOS (r12-lbb-3.png). A first attempt at 22:30 was OOM-killed on the host (3 VMs × 4 GB); rerun alone |
| full UEFI | the i12 live session (r12-i12-2.png, Calamares started from it) |

### Round 12 offline install i12 (full ISO, UEFI, `-nic none`, 40 GB virtio, keyboard only)
- Same test-only live tweak (partition.conf erase default). Europe/Rome, American English for language and formats, keyboard English (US), user Tester / tester, throwaway password (shots/i12-03…i12-07).
- Applications page (i12-08-apps.png): the new group **Extra apps (downloaded after install)** is unselected, with 6 individual unselected checkboxes: Cursor, Grok Bot, Rebased, RustDesk, Shotcut, Teams for Linux.
- Selection (i12-09-apps.png): all 7 package groups (VoxType ticked by hand) plus the extra apps **Cursor** and **RustDesk**, so the group shows as partially checked. Install started at 22:42:46 (i12-12.png).

### Round 12 progress 22:51
- Full ISO BIOS live (lfb): PASS 22:51. Desktop reached (r12-lfb-2). Terminal checks (r12-lfb-3/4): base 0.1.7, calamares-settings 0.2.11, firstboot 0.2.5, session 1.0.4-1, strata 1.1.1-1, no telegram-desktop deb, Telegram Flatpak present, Enabled: yes, 6 extra-app netinstall entries, payload 10 AppImages, 0 removed/optional names, BIOS firmware, offline `apt-get update` rc=0.
- i12 install at 22% at 22:49 (i12-14).
- Full ISO UEFI live (lfu): PASS 22:56. Desktop reached (r12-lfu-1), with the same terminal results as lfb (r12-lfu-2) and firmware=UEFI. **All 4 round-12 live boots pass.**
- i12 install: 23:03 77% "Install packages" (offline pool, i12-16/17); **"All done." by 23:18** (i12-18). There were no error dialogs; the live terminal showed only the usual benign `chcon: failed` lines. Install time was about 36 min under TCG.

### Round 12 i12 installed system (disk boot 23:24, login 23:29; shots i12-19..22, offline inspection build/i12-check.txt)
- PASS: optional packages 24/24 (all 7 package groups incl. VoxType); 10 bundled AppImages in ~/AppImages (bleachbit, elecwhat, localsend, marktext 0.19.1, obsidian, onlyoffice, 3× openra, task_manager_tmog); no openspot/cursor/rustdesk/other extras; locale en_US.UTF-8 (/etc/default/locale + `locale`); Europe/Rome; xfconf power-button-action = 4 in the session (user channel 4, /etc/xdg default 3); `fc-match` → JetBrainsMono Nerd Font (monospace → JetBrainsMono Nerd Font Mono); OpenRA content ra 151 / cnc 115 / d2k 590 files plus maps; omaxian-session 1.0.4-1, omaxian-strata 1.1.1-1, omaxian-base 0.1.7, firstboot 0.2.5; omaxian.sources `Enabled: yes`; live packages removed; VoxType 1.1.1 (omaxian-voxtype 1.1.1-2).
- The in-session `ls ~/AppImages | wc -l` showed 7 only because user-firstrun was still copying (mtimes 23:28–23:29); the offline check shows 10.
- **FAIL: Extra-apps picks and the Telegram pick are not recorded.** /var/lib/omaxian/optional-appimages.list and optional-flatpaks.list are both empty (created empty by omaxianoptional at 23:11:18), although Cursor + RustDesk and Telegram were ticked (i12-09-apps). As a consequence firstboot removed the preinstalled Telegram Flatpak offline ("removed (group not selected)") and wrote firstboot.done at 23:25:59 ("everything installed offline"), because it saw no pending extras. `curl` (the carrier package of the extras) ended up in optional-packages.list.
- **Root cause:** Calamares 3.3.14 netinstall ignores `pre-install`/`post-install` on *package* entries. `PackageTreeItem(…, PackageTag)` only reads name/description; scripts are read only for groups, and `getItemPackages()` only emits package items. So `packageOperations` carries plain names ("flatpak", "curl"), and the `omaxian-optional-flatpak select` / `omaxian-optional-appimage select` steps never run. The unit tests called the selectors directly, so they could not catch this. This also affects the round-11b Telegram design; i11 never reached the installed-system check.

## Round 12b: fix for the pick recording (2026-10-26, 23:33– CET)
- **Fix (3e40b29, omaxian-calamares-settings 0.2.12):**
  - netinstall.conf: the Telegram group's only entry is the marker `"omaxian-pick:flatpak:org.telegram.desktop"`, and each Extra-apps checkbox is `"omaxian-pick:appimage:<id>"`. There are no `post-install` keys any more, and no `curl`/`flatpak` carrier packages.
  - New Python job `omaxianpicks`, sequenced right before `packages`. It reads `packageOperations` from global storage and records the selected markers into /var/lib/omaxian/optional-flatpaks.list and optional-appimages.list in the target (both always created). It then removes the markers from `packageOperations` (an op left empty is dropped) so apt never sees them. It validates the ids (`[A-Za-z0-9._-]+`) and ignores malformed markers with a warning.
  - omaxianoptional also skips any `omaxian-pick:` name.
  - omaxian-firstboot is unchanged (0.2.5). Its `omaxian-optional-*` helpers stay for manual use.
- Tests: test-optional-appimages 17/17 and test-optional-flatpaks 11/11 now drive the real data path (plain marker names in `packageOperations` → omaxianpicks → omaxianoptional) and check the settings.conf sequence. firstboot-offline 22/22 and voxtype 25/25 pass, as do the others.
- Package rebuilt, repo-local updated (0.2.12 only, signed by 5CD4C2DB…4E75). Old i12 disk deleted. Chain tools/diag/r12b-chain.sh started at 23:35:41.
- r12b chain: base rootfs 23:35:41 → base ISO 23:37:31 → full rootfs 23:38:39 → full ISO 23:41:41 → ALLDONE 23:44:45. `sha256sum -c` OK for both. rootfs-full static check: netinstall.conf has the 7 `omaxian-pick:` markers (Telegram + 6 extras) and 0 `post-install`; calamares-settings 0.2.12; the omaxianpicks module is present; no telegram-desktop deb.
- Round-12b live boots, all with the untouched default GRUB entry and no network:

| boot | result |
|---|---|
| base UEFI (lbu) | PASS 23:43 (r12b-lbu-2/3) |
| base BIOS (lbb) | PASS 23:47 (r12b-lbb-1/2) |
| full UEFI (i13 live session) | PASS 23:54 (r12b-i13-c1/c2) |
| full BIOS (lfb) | PASS 23:54 (r12b-r12b-lfb-c1/c2) |

  Every boot showed base 0.1.7, calamares-settings 0.2.12, firstboot 0.2.5, session 1.0.4-1, strata 1.1.1-1 and `Enabled: yes`, with 7 pick markers and the omaxianpicks module present. Offline `apt-get update` gave rc=0 with 9 W: lines and 0 E: lines. The firmware matched the mode. Full ISO only: 9 Flatpaks including org.telegram.desktop, no telegram-desktop deb, a payload of 10 AppImages, and 0 removed or extra names.

### Round 12b install i13 (full ISO, UEFI, `-nic none`, 40 GiB virtio)
- Same test-only live tweak (partition.conf erase default). Europe/Rome, American English for language and formats, keyboard English (US), Erase disk (EFI 512 MiB plus ext4, swap to file). User Tester / tester / tester-standardpc, throwaway password (shots/r12b-i13-03…07).
- Applications page (r12b-i13-08-apps): **Extra apps (downloaded after install)** shows 6 individual checkboxes (Cursor, Grok Bot, Rebased, RustDesk, Shotcut, Teams for Linux), all unselected by default, and Telegram (Flatpak) is checked by default. Ticked: VoxType, **Cursor** and **RustDesk**, so all 7 groups plus 2 extras are selected (r12b-i13-09-apps). Summary: r12b-i13-10. Install started 23:57 (r12b-i13-12).
- Install finished "All done" at 00:43 (r12b-i13-18). It went through `omaxianpicks` and `packages` without errors and spent its usual long time at 78% "Install packages".
- Pre-boot read-only look at the disk: optional-appimages.list = `cursor`, `rustdesk`; optional-flatpaks.list = `org.telegram.desktop`; optional-packages.list = the 24 ticked packages, with **no `curl`** (the r12 leak is gone).
- The installed disk booted UEFI offline, then greeter (r12b-i13-20), then Tester desktop (r12b-i13-21). In-session checks (r12b-i13-22/23) and offline check (build/i13-check.txt):

| check | result |
|---|---|
| Picks recorded (Cursor, RustDesk, Telegram) | PASS |
| Extras stay pending offline: firstboot log "extra AppImage cursor/rustdesk picked, download pending (needs network)" and **no firstboot.done** | PASS |
| Telegram Flatpak kept (picked) | PASS |
| ~/AppImages = 10 bundled, 0 removed/extra names (openspot, cursor, rustdesk, shotcut, rebased, grok, teams) | PASS |
| Optional apt packages installed 24/24; live packages removed (calamares-settings absent) | PASS |
| omaxian.sources `Enabled: yes`; offline `apt-get update` rc=0, 9 W: lines, 0 E: lines | PASS |
| xfconf power-button-action = 4 (/etc/xdg default 3, user channel 4) | PASS |
| JetBrainsMono Nerd Font (36 faces) | PASS |
| LANG/LC_* en_US.UTF-8, Europe/Rome | PASS |
| OpenRA content ra 151 / cnc 115 / d2k 590, plus maps | PASS |
| omaxian-session 1.0.4-1, omaxian-strata 1.1.1-1, base 0.1.7, firstboot 0.2.5, VoxType 1.1.1 | PASS |

  **Round 12b: PASS.** The r12 FAIL (picks not recorded) is fixed by calamares-settings 0.2.12.
- Final ISOs (`sha256sum -c` OK):

| ISO | bytes | sha256 |
|---|---|---|
| out/omaxian-base-0.1-trans-siberian-shaman-amd64.iso | 2467051520 | 36567093a0986383e101679e1e6dead5b4321305bafd269749b1c32dd109257f |
| out/omaxian-full-0.1-trans-siberian-shaman-amd64.iso | 8874823680 | ad4a51a29a8d45feeb4cca84db374b1b888d01ca25f1b04d21a62d493bc2e01a |

- Cleanup: VMs killed. Test disk, raw export, OVMF vars and throwaway password file deleted. Leftover diag http.server (127.0.0.1:8765) stopped. Nothing uploaded, published or pushed.

## Publish 0.1.7 (2026-10-27, 06:19–06:31 CET)

Approved by the owner. Done with rclone (R2 S3, Cloudflare, 64M chunks, concurrency 4).

- **apt (s3://omaxian-apt → https://apt.omaxian.org):** published in order: pool (Cache-Control `public, max-age=31536000, immutable`), then dists (`max-age=300`, sync with delete), then keyring (`max-age=3600`). `rclone check --download` against repo-local: 0 differences, 14 matching files. The 5 superseded pool objects were removed: omaxian-base 0.1.6, omaxian-firstboot 0.2.3, omaxian-calamares-settings 0.2.9, omaxian-session 1.0.3-4, omaxian-strata 1.1.0-1 (none of them referenced by the new Packages). branding 0.2.5 and fonts-nerd 3.5.1-1 were byte-identical and left as they were.
- **HTTPS checks:** InRelease has a Good signature from subkey 5CD4C2DB…AF4C4E75 using the published keyring, which is byte-identical to keys/public and to the keyring in omaxian-base 0.1.7. The 3 index sha256s match Release. All 7 Filename URLs return 200. Isolated apt root with the omaxian.sources shipped in omaxian-base 0.1.7: `apt-get update` rc=0 with no W:/E:. Candidates are base 0.1.7, calamares-settings 0.2.12, session 1.0.4-1, strata 1.1.1-1, the same versions as in out/omaxian-{base,full}.packages. voxtype is not in the repo.
- **ISOs (s3://omaxian-iso/releases/0.1/ → https://download.omaxian.org/releases/0.1/):** both replaced. Content-Length matches local (2467051520 and 8874823680). The .sha256 files are byte-identical to the local ones. The full streamed sha256 from R2 matches: base 36567093…09257f, full ad4a51a2…2e01a. No unfinished multipart uploads are left in either bucket.
- R2 answered some uploads with `501 NotImplemented` after the object had been written. It is harmless; the rclone retry then found the object complete.

## Round 13 (2026-11-01): owner's VM test of the 0.1.7 ISOs

Reported on both ISOs: no installer icon (i3 has no desktop); Omaxian Menu > installer does nothing; from a terminal the installer stays on its first page with a spinner forever; running `~/Desktop/omaxian-install.desktop` printed `[Desktop: command not found`.

**Findings (r13a: base ISO, UEFI, `-nic none`, no disk; r13b: base ISO, UEFI, user-mode NIC, 30G disk):**
- **Menu does nothing (reproduced, fixed).** Menu actions and app entries are started detached (`Quickshell.execDetached` / `setsid -f`), so `/usr/bin/omaxian-install` is orphaned (parent = init). It ran `exec pkexec …`, and pkexec refuses to work for a process whose parent is init: "Refusing to render service to dead parents." (seen in r13a). Fix: omaxian-install keeps itself as pkexec's parent (no `exec`), uses `/usr/bin/pkexec /usr/bin/env DISPLAY=… XAUTHORITY=… calamares` with DISPLAY/XAUTHORITY defaulted (the live polkit rule only matches that exact command line), and focuses the running window instead of starting a second instance. Patched in the r13a live overlay: Omaxian Menu > Install Omaxian OS opened Calamares without a password prompt (shots/r13a-16 before, r13a-17 after). Super+Shift+I already worked (r13a-4).
- **Spinner (reproduced, cause found).** The welcome page shows after about 8 s under TCG. Calamares 3.3 then re-runs all requirement checks every ~5 s, with a countdown spinner, for as long as *any* check is unsatisfied, mandatory or not. Our `internet` check (non-mandatory) is never satisfied offline. In r13b, with the user-mode NIC, the page still said "The system is not connected to the Internet" (shots/r13b-4), so the spinner never ends there either. Fix: `internet` removed from welcome.conf `check` (the install is offline; netinstall uses local groups). The owner's terminal attempt ran the .desktop file as a shell script (`[Desktop Entry]` → `[Desktop: command not found`); the installer itself was started some other way.
- **Desktop file:** i3 draws no desktop icons, so ~/Desktop/omaxian-install.desktop was useless. It is no longer created (and is removed if present).

**Changes:**
- calamares-settings 0.2.13: launcher fix and welcome checks as above. The live session now autostarts the installer once per session, after i3 answers `get_version` and the Omaxian shell (quickshell, which also hosts the polkit agent) is running, via the same `/usr/bin/omaxian-install` as the menu. `omaxian.noinstaller` on the kernel command line skips it. Adds an "Install Omaxian OS" item to the Omaxian Menu (user extension jsonc; search "install"). The notification (after 30 s) now explains how to reopen the installer after closing it. Installed users join `input`. All live-only pieces stay behind boot=live and are deleted by calamares-post.
- Live user: `input` added to LIVE_USER_DEFAULT_GROUPS.
- omaxian-ydotool 1.0.4-1 (new): built from ReimuNotMoe/ydotool tag v1.0.4, commit 57ba7d0af525e82da2de0e275d169477f293b197, source archive sha256 ba075a43aa6ead51940e892ecffa4d0b8b40c241e4e2bc4bd9bd26b61fde23bd (scripts/fetch-ydotool.sh). cmake/scdoc are build-time only; runtime depends on libc6 and kmod. Conflicts/Replaces/Provides the Debian `ydotool` (backports 1.0.4-2~bpo13+1). Ships udev `KERNEL=="uinput", GROUP="input", MODE="0660"` and /etc/modules-load.d/omaxian-uinput.conf. Once per user, Xsession.d/36omaxian-ydotool creates ~/.local/bin/ydotoold → /usr/bin/ydotoold and ~/.config/i3/config.d/50-ydotool.conf containing `exec --no-startup-id ~/.local/bin/ydotoold`. YDOTOOL_SOCKET is not needed: daemon and client both use $XDG_RUNTIME_DIR/.ydotool_socket. tests/test-ydotool.sh 16/16.
- easyeffects (20-audio.list) and cmatrix (40-user.list) are in both ISOs. easyeffects pulls in only libpulse0 from PulseAudio (no daemon); PipeWire stays from backports.
- omaxian-session 1.0.6-1: Omaxian shell v1.0.6 (Omarchy v4.5.0-rc2). It built without patch changes. Upstream's `version` file still says v1.0.5, so the package version is now taken from OMAXIAN_SHELL_REF (the build warns on a mismatch).
- omaxian-voxtype 1.1.1-3: **existing bug found** while checking the input-group impact. `voxtype -q daemon --clipboard` is rejected by voxtype 1.1.1 ("unexpected argument '--clipboard'"; options go before the subcommand), so Super+Ctrl+V never started the daemon. It is now `voxtype -q --no-hotkey --clipboard daemon`. `--no-hotkey` keeps VoxType's evdev hotkey off now that users are in `input`.
- tests: test-live-installer-hint 16/16 (no Desktop file, menu item valid after JSONC stripping and merged into an existing file without duplicates, omaxian-install not exec'ing pkexec, defaults, single instance, autostart wiring), test-voxtype 25/25, test-ydotool 16/16.

**Rebuild (r13 chain, 16:17–16:26 CET):** the first r13 base build carried two kernels (backports 7.2.11 next to 7.2.9: the s_upgrade cleanup only removed non-7.x kernels), which made the base ISO 2914060288 bytes. s_upgrade now purges every linux-image/modules/headers package except the one linux-image-amd64 depends on (commits c84feeb, 46c028b). After the rebuild both rootfs have only 7.2.11+deb13. The base ISO is 2615066624 bytes and the full ISO 9206335488 bytes. The full rootfs has cmatrix 2.0-6, easyeffects 7.2.3-1, omaxian-ydotool 1.0.4-1, session 1.0.6-1, calamares-settings 0.2.13, and 9 flatpaks.

**Live tests (progress):**
- r13c-bu, base, UEFI, `-nic none`, no disk: the installer started on its own and the welcome page loaded (shots/r13c-bu-3). The only remaining spinner is Calamares re-checking the two real mandatory failures (no disk → "not enough drive space", "no partitions"), which is expected without a disk. Closing it (Super+W, Yes) worked (bu-4/5). Super+Shift+I reopened it (bu-6). Omaxian Menu > search "install" > Install Omaxian OS reopened it (bu-7/8). PASS.
- r13c-bb, base, BIOS, user-mode NIC, 30G disk: the installer started on its own. The welcome page loaded with no requirement warnings and **no spinner** (shots/r13c-bb-1). Close, then Super+Shift+I, then close, then Menu > "install" each worked (bb-2…5). PASS.
- r13c-fi, full, UEFI, `-nic none`, 40G disk (install VM): the installer started on its own and the welcome page loaded with no spinner (r13c-fi-1). In the live terminal (fi-2/3): `id` includes 101(input); no ~/Desktop; config.d has 50-ydotool.conf and 90-omaxian-live-installer.conf; `pgrep -a ydotoold` shows /home/omaxian/.local/bin/ydotoold; /dev/uinput is `crw-rw---- root input`; `ydotool type 'echo YDO$((40+2))'` typed into the terminal and printed YDO42.
- Install i14 (same VM): the usual test-only live tweak (partition.conf erase default). Europe/Rome, American English, keyboard English (US), Erase disk (EFI 512 MiB + ext4, swap to file). User Tester / tester / tester-standardpc with a throwaway password; default app selections. Install started 16:38 (r13c-fi-i03…i11).
- r13c-fb, full, BIOS, `-nic none`, no disk: the installer started on its own and the welcome page loaded (r13c-fb-1; the only spinner is the expected no-disk recheck). Close, then Super+Shift+I (fb-2), then close, then Menu > "install" (fb-3), then close (fb-4) all worked. PASS.
- i14 finished "All done" at 17:10, about 32 min (r13c-fi-i12…i15).
- Offline look at the i14 disk (read-only): `id tester` includes 101(input) (and 995(libvirt), 102(kvm)). cmatrix 2.0-6, easyeffects 7.2.3-1, omaxian-ydotool 1.0.4-1 and session 1.0.6-1 are installed; pulseaudio is not. /usr/bin/ydotool{,d}, the uinput udev rule and modules-load are present. calamares, calamares-settings and live-boot are removed, and there is no ~/Desktop. Only one kernel (7.2.11). The installer log is still not copied to the target (a known gap since round 1; no preservefiles module is configured).
- Installed i14 booted UEFI offline to the greeter (r13c-fi-b1); the Tester desktop came up with **no installer window** (b2). Terminal checks (b3–b5):

| check | result |
|---|---|
| `id` includes 101(input) | PASS |
| ydotoold running from ~/.local/bin/ydotoold (symlink → /usr/bin/ydotoold) | PASS |
| ~/.config/i3/config.d/50-ydotool.conf = `exec --no-startup-id ~/.local/bin/ydotoold` | PASS |
| /dev/uinput `crw-rw---- root input`, uinput module loaded | PASS |
| `ydotool type` types into the terminal (YDO42) | PASS |
| ~/.local/bin in PATH | PASS |
| easyeffects 7.2.3-1, cmatrix 2.0-6 (runs), omaxian-ydotool 1.0.4-1; no pulseaudio | PASS |
| omaxian-session 1.0.6-1; power-button-action 4; keyboard layout us | PASS |
| No installer autostart, no Calamares process, no live-installer config.d fragment, no menu item ("install" finds only GDebi), no ~/Desktop | PASS |
| Installer log copied to target | not done (known gap, see open issues) |

**Round 13 result: PASS** (both ISOs, UEFI and BIOS live; full ISO offline install).

| test | base | full |
|---|---|---|
| Live UEFI `-nic none`: autostart, welcome page, Super+Shift+I, Menu item | PASS (r13c-bu) | PASS (r13c-fi) |
| Live BIOS: autostart, welcome page, Super+Shift+I, Menu item | PASS, user NIC + disk, no spinner (r13c-bb) | PASS, `-nic none` (r13c-fb) |
| Offline install + checks above | n/a | PASS (i14) |

- Final ISOs (`sha256sum -c` OK; .sha256 files in out/):

| ISO | bytes | sha256 |
|---|---|---|
| out/omaxian-base-0.1-trans-siberian-shaman-amd64.iso | 2615066624 | 9d49f7c5f8cd2d43917bb02edf7cce7189774e0c152c8ad73fb3434ae6151bbe |
| out/omaxian-full-0.1-trans-siberian-shaman-amd64.iso | 9206335488 | 434355df6c90264f8c4e5bfcc83945a58ad174f03513505c363564ee33da06fd |

- Open issues: (1) the installer log is not persisted to the target (a Calamares `preservefiles` entry would fix it; not done, to avoid another rebuild). (2) Upstream Omaxian v1.0.6 still has `version` = v1.0.5. (3) The Omarchy pin is an rc (v4.5.0-rc2). (4) Calamares still shows its 5 s recheck spinner when a *mandatory* check fails (no or too small disk); that is expected and the page says why. (5) Membership in `input` lets user processes read all keyboard and mouse events (needed for ydotool and VoxType). (6) The VoxType daemon was not exercised in this round beyond the unit tests. (7) The base ISO is 148 MB larger than 0.1.7 (easyeffects and its deps, cmatrix, ydotool, kernel 7.2.11).
- Cleanup: VMs killed. Test disks, OVMF vars, screendump ppm and the throwaway password file deleted. Nothing uploaded, published or pushed.

## Publish round 13 (2026-11-01, 17:40–17:45 CET)

Approved by the owner. Done with rclone, the same way as 0.1.7 (R2 S3, 64M chunks, concurrency 4; size checked after each upload, no `--ignore-times`).

- **Repo check before publishing:** repo-local holds omaxian-base 0.1.7, branding 0.2.5, calamares-settings 0.2.13, firstboot 0.2.5, fonts-nerd 3.5.1-1, session 1.0.6-1, strata 1.1.1-1 and ydotool 1.0.4-1, all byte-identical to out/debs. These are exactly the omaxian-* versions in out/omaxian-{base,full}.packages. omaxian-voxtype is not in the repo; on the full ISO it sits only in the offline pool. InRelease has a GOODSIG/VALIDSIG from subkey 5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75. The Release sha256s match. The keyring is identical to keys/public.
- **apt (s3://omaxian-apt):** published in order: pool (`public, max-age=31536000, immutable`), dists (`max-age=300`, sync), keyring (`max-age=3600`, unchanged, so it was not re-uploaded). `rclone check --download` showed no differences apart from the 2 superseded objects. Those were deleted, since the new Packages no longer references them: calamares-settings 0.2.12 and session 1.0.4-1. As before, R2 answered `501 NotImplemented` on the first attempt and the retry found the objects complete.
- **ISOs (s3://omaxian-iso/releases/0.1/):** both ISOs and both .sha256 files replaced. Over HTTPS (download.omaxian.org), Content-Length is 2615066624 and 9206335488, matching the local files. The .sha256 files are byte-identical to the local ones. The full streamed sha256 matches: base 9d49f7c5…6151bbe, full 434355df…ee33da06fd.
- **HTTPS apt checks:** InRelease and Packages are byte-identical to repo-local. InRelease has a Good signature with the published keyring, which equals the keyring shipped in omaxian-base 0.1.7. All 8 Filename URLs return 200 with the immutable Cache-Control. An isolated apt root using base 0.1.7's omaxian.sources gives `apt-get update` rc=0 with 0 W:/E: lines. Candidates: base 0.1.7, calamares-settings 0.2.13, session 1.0.6-1, strata 1.1.1-1, ydotool 1.0.4-1; voxtype is absent. The downloaded debs are byte-identical to out/debs.
- No unfinished multipart uploads are left in either bucket. Nothing else in the buckets was changed. Nothing was pushed.

## Round 14 (2026-11-01, 19:55– CET): owner's base VM test follow-ups

Owner feedback after installing the base ISO: no Documents/Downloads/Videos folders, OnlyOffice should be in the base ISO, and questions about docker-compose, Thunar and adding apps later. Nothing uploaded, published or pushed in this round.

### Findings

- **No XDG user folders (bug).** `Xsession.d/25omaxian-home` (omaxian-seed-home) copies the home template first. `35omaxian-user-setup` then sees a seeded home (`omarchy-launch-shell` + `.xsessionrc`) and exits *before* its `xdg-user-dirs-update` line. i3 does not run the XDG autostart entry (`/etc/xdg/autostart/xdg-user-dirs.desktop`), so nothing else creates them. Same in the live session. Fix (omaxian-session 1.0.6-2): `xdg-user-dirs-update` runs on every login before the early exit (idempotent, localized: LANG comes from /etc/default/locale). Desktop is kept: i3 draws no desktop, so the folder is harmless.
- **docker-compose:** from the **Containers** optional group (`podman podman-docker podman-compose buildah docker-compose distrobox`), which is ticked by default (`selected=true`, like every group except VoxType and the extra apps). It is not in out/omaxian-base.packages; on a base install it comes from Calamares (online) or omaxian-firstboot (offline install, at the first online boot). No change.
- **Thunar:** a hard `Depends` of omaxian-session (upstream Omaxian `scripts/setup.sh` lists `thunar` as the XFCE file manager) and also pulled in by the `xfce4` metapackage (XFCE alternative session) and `thunar-archive-plugin` (30-desktop.list). In the Omaxian shell it is the fallback of `omarchy-launch-files` (Super+Shift+F, `$file_manager`) and of directory opening: the inode/directory default is Strata (`io.github.lgse.Strata.desktop;thunar.desktop;` in mimeinfo.cache), Thunar is second. It is also the XFCE session's file manager and handles volumes (thunar-volman). Removing it would need dropping `xfce4` too. No change.
- **Adding apps later:** no command existed (omaxian-optional-appimage/-flatpak only record installer picks). New `omaxian-optional` (omaxian-firstboot 0.2.6), see README "Optional groups and apps".

### Changes

- omaxian-session 1.0.6-2: XDG user folders on every login.
- appimages.manifest: OnlyOffice → class `base` (in both ISOs). build-rootfs: new stage `payload` (base rootfs): copies class-base AppImages + omaxian-voxtype .deb (5 KB) into /usr/share/omaxian/payload; the full build copies the other bundled rows as before.
- omaxian-firstboot 0.2.6: omaxian-appimage-fetch skips class `base` while the bundled copy exists (no re-download) and accepts `OMAXIAN_APPIMAGE_ONLY`; omaxian-user-firstrun makes a plain menu entry from the AppImage's own .desktop/icon until Gear Lever integrates it (removed then); new `omaxian-optional` CLI + menu entry "Add optional apps" (Terminal=true); ships optional-groups(.full).list and voxtype.pin.
- tests/test-omaxian-optional.sh (15 checks) PASS; tests/test-optional-appimages.sh updated (17 PASS); all other tests unchanged and passing.
- README: optional groups table, base vs full, omaxian-optional, manual apt/flatpak commands.

### Progress log

- 20:02 packages built (session 1.0.6-2, firstboot 0.2.6), repo-local refreshed (local only).
- 20:03 r14 build chain started (tools/diag/r14-chain.sh).
- 20:09 owner steering: installer picks ticked by default (Flatpaks Packet, Gear Lever, Telegram, Discord; AppImages LocalSend, ElecWhat, Obsidian, MarkText). First chain stopped during the full ISO squashfs (it had the old configuration).

### Changes (installer picks, 20:10–20:15)

- Flathub IDs checked on flathub.org (API v2, 20:10): `io.github.nozwock.Packet` (Packet, "Share files easily", 4.4 MB download / 10.5 MB installed, GNOME 50), `it.mijorus.gearlever` (Gear Lever, 11.6 / 26.3 MB, GNOME 50), `com.discordapp.Discord` (Discord, 252 / 596 MB, freedesktop 26.08), `org.telegram.desktop` (Telegram, 114 / 249 MB).
- config/flatpaks.list: Packet, Gear Lever and Discord removed (always-installed list). They are now optional groups `share-packet`, `gearlever` and `chat-discord` (selected=true, Flatpak only, like `chat-telegram`). Base: installed by firstboot from Flathub when picked. Full: preinstalled as before and removed offline at first boot when unticked. **Full ISO size impact: none**, because all three were already preinstalled in r13.
- appimages.manifest: new class `pick` for elecwhat, localsend, marktext and obsidian. They stay bundled in the full payload (no size change) and get their own ticked checkbox in the new netinstall group "Apps (AppImages)", with the existing `omaxian-pick:appimage:<id>` marker. With no record (not a Calamares install) they count as picked. omaxian-appimage-fetch skips an unpicked pick row; omaxian-user-firstrun does not copy it; full_offline_complete ignores it. The "Extra apps" checkboxes stay unticked.
- omaxian-user-firstrun: when Gear Lever is unticked, the plain menu entries are final, so the run completes instead of staying pending.
- omaxian-firstboot --boot: waits for the network as long as the machine is up (10 s polling for 10 min, then every minute), instead of giving up after 10 min until the next boot.
- omaxian-optional: lists the new groups and pick AppImages ("installer pick; full ISO"). An install without an installer record no longer creates optional-flatpaks.list or optional-appimages.list, because a new record would unpick the other defaults.
- omaxian-calamares-settings 0.2.14 (netinstall now has 9 groups on base, 10 on full, plus the two AppImage groups). omaxian-firstboot 0.2.6 changelog extended.
- Tests: test-optional-appimages 25 PASS (8 new pick and Gear Lever checks), test-omaxian-optional 16 PASS, test-optional-flatpaks 11 PASS, test-voxtype 25 PASS; the rest are unchanged and pass (test-omaxian-sources-upgrade needs old/new .deb arguments and was not run).
- 20:15 packages rebuilt, repo-local refreshed (local only); r14 chain restarted at 20:15:39.
- 20:28 r14 chain ALLDONE. Base ISO 3 039 420 416 bytes (r13: 2 615 066 624, +424 MB for OnlyOffice). Full ISO 9 204 375 552 bytes (r13: 9 206 335 488). Build log: "payload (base): 1 AppImage(s) of class base (407M)", "payload: 10 bundled AppImages (1.1G)". rootfs-full flatpaks: 9 apps, including Discord, Packet, Gear Lever and Telegram. netinstall.conf has 14 `selected: true`. `sha256sum -c` OK for both .sha256 files (written by build-iso).
- 20:21 base live UEFI (VM i15, `-nic none`): the desktop came up and **Calamares autostarted** (shots/r14-i15-02). Home dirs Desktop, Documents, Downloads, Music, Pictures, Public, Templates and Videos are present in the live session (r14-i15-04). The payload has onlyoffice_desktopeditors.appimage.
- 20:27 base install i15: test-only live tweak (partition.conf erase). Europe/Rome, American English, English (US) keyboard, Erase disk. User Tester / tester, throwaway password. Applications page (r14-i15-10): Telegram, Discord, Packet and Gear Lever ticked; "Apps (AppImages)" has ElecWhat, LocalSend, MarkText and Obsidian ticked; the 6 Extra apps are unticked. **Unticked for the test: Discord, Gear Lever, Obsidian** (r14-i15-12). Install started 20:29.
- docs/iso-size.md: new section "Base ISO: OnlyOffice and installer picks".
- 20:35 base install i15 finished ("All done", r14-i15-19). First boot of the installed disk, offline (`-nic none`): user dirs Desktop, Documents, Downloads, Music, Pictures, Public, Templates and Videos are present in /home/tester (r14-i15-22). ~/AppImages/onlyoffice is copied from the bundled payload and not downloaded. Its plain menu entry is present because Gear Lever is unticked (r14-i15-22/26). /var/lib/omaxian/optional-flatpaks.list = org.telegram.desktop and io.github.nozwock.Packet (no Discord, no Gear Lever). optional-appimages.list = elecwhat, localsend and marktext (no obsidian); firstrun skips Obsidian (r14-i15-24). `omaxian-optional status` lists the groups and picks with their state (r14-i15-25). /usr/share/applications/omaxian-optional.desktop ("Add optional apps") is present (r14-i15-26). Launching it from the Quickshell menu could not be driven by keyboard in the VM. `omaxian-optional` from a terminal works.
- 21:17 i15 rebooted with `-nic user`. omaxian-firstboot --boot detected the network and started "apt: installing optional packages" (chromium … docker-compose …). Every HTTPS fetch fails with "SSL: unexpected eof" via the sandbox proxy 198.18.0.1 (r14-i15-30/31), so the picked flatpaks and AppImages were not downloaded here. firstboot keeps retrying (package-by-package fallback seen at 21:26, r14-i15-33); ~/AppImages still has only onlyoffice, and `flatpak list` is empty (r14-i15-32). This is a test-environment limit, not a product failure. Online download of the picks is **not verified** in this round.
- Cosmetic, not fixed: `omaxian-optional status` shows the bare id as the label for some AppImages (bleachbit, onlyoffice, openra-*, task_manager_tmog).
- 21:27 full live UEFI (VM i16, `-nic none`): **Calamares autostarted** (shots/r14-i16-01). Home dirs Desktop … Videos are present in the live session. `flatpak list` shows 9 apps, including Discord, Packet, Gear Lever and Telegram (r14-i16-04).
- 21:33 full install i16: erase tweak, user Tester. The Applications page has all 10 groups, with the picks ticked by default and VoxType and Extra apps unticked (r14-i16-08). **Unticked for the test: Discord and LocalSend** (r14-i16-09). Install started 21:35.
- 21:50 base live **BIOS** (VM b1, SeaBIOS, `-nic none`, no disk): **Calamares autostarted**. The only warnings are the expected no-disk ones (shots/r14-b1-02). Cancel worked (r14-b1-03). In a terminal (r14-b1-04): /sys/firmware/efi is absent (= BIOS), the home dirs Desktop … Videos are present, and calamares-settings 0.2.14 and firstboot 0.2.6 are installed. PASS. VM killed 21:57.
- 22:02 full install i16 finished ("All done", r14-i16-16; ~27 min under TCG). It was booted from disk at 22:11 (`-nic none`, fresh OVMF vars) and LightDM showed the Tester login (r14-i16-17). After login **the installer did not autostart** (r14-i16-18). Terminal checks (r14-i16-19):
  - The home dirs are AppImages, Desktop, Documents, Downloads, Music, Pictures, Public, Templates and Videos.
  - ~/AppImages has bleachbit, elecwhat, marktext, obsidian, onlyoffice, openra ×3 and task_manager_tmog. **LocalSend was not copied** (unticked).
  - optional-flatpaks.list = telegram, Packet and gearlever. optional-appimages.list = elecwhat, marktext and obsidian.
  - `flatpak list`: Proton Mail Bridge, GPU Screen Recorder, G4Music, Packet, Podman Desktop, Gear Lever, Telegram and Zoom. **Discord was removed offline** ("flatpak com.discordapp.Discord: removed (group not selected)").
  - The firstboot log ends with "full ISO: everything installed offline, first boot provisioning complete".
  - The user is in the `input` group (plus sudo, kvm, libvirt …). /dev/uinput is `crw-rw---- root input`, and ydotoold is running from ~/.local/bin/ydotoold.
  - No calamares process, no Xsession.d live file, and 0 calamares packages are installed.

  PASS.

### Round 14 result

| Check | Base ISO | Full ISO |
|---|---|---|
| Live UEFI: Calamares autostarts | PASS (r14-i15-02) | PASS (r14-i16-01) |
| Live BIOS: Calamares autostarts | PASS (r14-b1-02) | not rerun (r13 PASS, unchanged boot path) |
| Live home dirs (Documents, Downloads, Videos …) | PASS | PASS |
| Offline install (UEFI, erase) | PASS (i15) | PASS (i16) |
| Installed XDG home dirs | PASS | PASS |
| Installer does not autostart on installed system | PASS | PASS |
| OnlyOffice in ~/AppImages from the payload, no download | PASS (+ plain menu entry without Gear Lever) | PASS |
| Picks ticked by default on the Applications page | PASS | PASS |
| Unticked flatpaks | Discord and Gear Lever not recorded, not installed | Discord removed offline at first boot |
| Unticked pick AppImages | Obsidian not recorded, skipped | LocalSend not copied |
| Ticked picks | recorded; online download **not verified** (sandbox HTTPS blocked) | present (Telegram, Packet, Gear Lever, ElecWhat, MarkText, Obsidian) |
| omaxian-optional status + "Add optional apps" .desktop | PASS (menu launch by GUI not driven) | – |
| input group, /dev/uinput, ydotoold | – | PASS |
| docker-compose | Containers group (preselected), pending until online | Containers group (preselected), offline pool (not separately checked in r14) |
| Thunar | omaxian-session Depends + xfce4 | same |
- 22:25 VMs killed; test disks, vars and password files deleted.

## Publish round 14 (2026-11-02, 08:49–08:58 CET)

Approved by the owner. Same method as round 13 (rclone, pool → dists → keyring, same Cache-Control).

- **repo-local check:** debs byte-identical to `out/debs`, versions equal `out/omaxian-{base,full}.packages`
  (calamares-settings 0.2.14, firstboot 0.2.6, session 1.0.6-2, base 0.1.7, branding 0.2.5,
  strata 1.1.1-1, ydotool 1.0.4-1, fonts-nerd 3.5.1-1); voxtype not in repo; InRelease/Release.gpg
  signed by subkey 5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75.
- **apt (s3://omaxian-apt):** 3 new debs uploaded; dists synced; keyring uploaded. Superseded pool
  objects deleted (no longer in Packages): session 1.0.6-1, calamares-settings 0.2.13, firstboot 0.2.5.
  `rclone check --download`: 0 differences.
- **HTTPS (apt.omaxian.org):** InRelease/Packages/keyring identical to repo-local, gpgv good signature;
  all 8 Filename URLs 200; isolated `apt-get update` clean (0 W/E), expected candidates, voxtype absent.
- **ISOs (s3://omaxian-iso/releases/0.1/), verified via download.omaxian.org:**
  - base: 3039420416 bytes, sha256 71ff60e3dc1180112059d0261452cbcc012f71690194bdbc1577e9cceee7f62a ✔
  - full: 9204375552 bytes, sha256 43ac556975bdaac37eb8939a2532a64e76325cbb80e6c860bbe2402a5d76003b ✔
  - `.sha256` files identical to local.
- R2 answered `501 NotImplemented` on first attempts (as in round 13); the rclone retry succeeded and content was verified.
- No leftover multipart uploads in either bucket. Nothing else in the buckets changed. Not pushed.

## Round 15 (2026-11-05, ~17:50–19:40 CET): Omaxian shell v1.1 + default community-apps

Owner released **v1.1** on github.com/aozora/omaxian (tag = main `ae527b75`; upstream `version` file still says v1.0.8 — packaging uses `OMAXIAN_SHELL_REF`). Community-plugins stay out.

### Build
- `OMAXIAN_SHELL_REF=v1.1` → Debian session **1.1.0-1** (> 1.0.6-2). `omaxian-base` **0.1.8**.
- New `scripts/build-community-apps.sh`: seeds four apps into the session home template:
  - **disktree** 0.11.0 — prebuilt `tobi/disktree` release tarball
  - **omarchy-meeting-recorder** — upstream `install.sh --binary` (prebuilt)
  - **monologue**, **signed** — qmake6 build in Devuan chroot via each app's `install.sh --skip-apt`
- Runtime deps from each app's `omaxian.deps.json` / install needs → `omaxian-session` Depends + `config/package-lists/55-community-apps.list` (both ISOs).
- Local signed apt repo rebuilt only (`repo-local/`); **not published**. ISOs rebuilt; **no R2 / no GitHub push**.

### Package versions (both ISOs)
| Package | Version |
|---|---|
| omaxian-session | 1.1.0-1 |
| omaxian-base | 0.1.8 |
| omaxian-calamares-settings | 0.2.14 |
| omaxian-firstboot | 0.2.6 |
| omaxian-branding | 0.2.5 |
| omaxian-fonts-nerd | 3.5.1-1 |
| omaxian-strata | 1.1.1-1 |
| omaxian-ydotool | 1.0.4-1 |

### ISOs
| Image | Path | Size | sha256 |
|---|---|---|---|
| base | `out/omaxian-base-0.1-trans-siberian-shaman-amd64.iso` | 3098339328 (≈2.9G) | `7b1bf01cd0df7e692714a16958fa8e414e00a5ce123bd7e8022af328061ecb7d` |
| full | `out/omaxian-full-0.1-trans-siberian-shaman-amd64.iso` | 9389113344 (≈8.8G) | `88c29b28b4e07034d96161a6219da7f28f3cd795b9b2b491cc5aed3776b88d99` |

Squashfs / rootfs: all four binaries + `.desktop` under `usr/share/omaxian/home-template/.local/`; plugins dir only `.gitkeep`. `ldd` clean; `--help` smoke OK in rootfs chroot.

### Live UEFI (base ISO, TCG, no disk) — PASS
- Desktop reached (~6 min). Calamares **autostarted** (shots/r15-base-uefi-0360s.png / now.png). Expected blocking errors with no disk (space / no partitions).
- Live user `omaxian@omaxian` (after fixing a build-time `box` uid-1000 pollution and rebuilding ISOs).
- Apps are seeded at first Xsession from the home template (same path as install). Interactive launch in live was not fully driven (Calamares ate focus); presence verified via squashfs + installed-system session.

### Offline base install i17 (UEFI, `-nic none`, 40G virtio) — PASS
- Test-only live tweak: `initialPartitioningChoice: erase` in partition.conf (same harness limit as rounds 7–14; mouse unreliable).
- Europe/Rome, American English, English (US) keyboard, Erase disk (EFI 512 MiB + ext4, swap to file). User Tester / tester / tester-pc.
- Applications: default picks. **"All done."** ~19:18 CET (shots/r15-i17-23-done.png). Reboot to greeter `tester-pc` / Tester (r15-i17-27-installed.png); desktop without installer (r15-i17-28-desktop.png).

### Installed system checks (shots/r15-i17-33-apps.png, 34-r14.png, 35-final.png, 36-input.png)
| Check | Result |
|---|---|
| omaxian-session 1.1.0-1, base 0.1.8, ydotool 1.0.4-1 | PASS |
| `~/.local/bin/{disktree,monologue,omarchy-meeting-recorder,signed}` + on PATH | PASS |
| disktree / signed `--help` / `help` | PASS (launchable CLI) |
| XDG dirs Desktop…Public | PASS |
| `~/AppImages/onlyoffice_desktopeditors.appimage` | PASS |
| `input` group (gid 101) | PASS |
| `/dev/uinput` | PASS (`uinput_ok`) |
| `ydotoold` running | PASS |
| calamares / calamares-settings purged | PASS (`calamares_gone`) |
| No installer window on installed desktop | PASS |

### Caveats
- Upstream Omaxian tag `v1.1` still ships `version` = 1.0.8; Debian version comes from the shell ref (normalized `v1.1` → `1.1.0`).
- Community-plugins not installed (only empty `plugins/.gitkeep` from shell layout).
- Build chroot briefly gained a host `box` uid-1000 user during Qt community-app staging; removed before final ISO rebuild.
- VM mouse still unusable for Calamares partition radio; erase default remains a **test-only** live overlay.
- GUI window launch of the four apps in the VM was not screenshot-driven (TCG + focus); CLI `--help` / PATH presence confirmed.
- Local apt only; **not** uploaded to R2, **not** published, **not** pushed to GitHub.

**Round 15 result: PASS** (live UEFI base; offline base install + community-apps + round-14 behaviours).

## Publish round 15 (2026-11-05, 19:44–19:53 CET)

Approved by the owner (widget t62s378). Same method as round 14 (rclone, pool → dists → keyring, same Cache-Control).

- **GitHub:** `aozora/omaxian-os` branch `omaxian-os-build` pushed to `c21355df0175e05bdc4159fb96ed7b7629d85855` (includes Round 15 build `c21355d` + Round 14 publish notes `562e13a`). Bundle → tatodx ff-only merge → push as `aozora`.
- **repo-local check:** debs byte-identical to `out/debs`; InRelease/Release.gpg signed by subkey 5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75. Versions: session 1.1.0-1, base 0.1.8, calamares-settings 0.2.14, firstboot 0.2.6, branding 0.2.5, strata 1.1.1-1, ydotool 1.0.4-1, fonts-nerd 3.5.1-1; voxtype not in repo.
- **apt (s3://omaxian-apt):** pool synced (2 new debs: session 1.1.0-1, base 0.1.8); dists synced; keyring present. Superseded pool objects removed: session 1.0.6-2, base 0.1.7. `rclone check --download`: 0 differences (8 pool + 6 dists). R2 `501 NotImplemented` on first attempt; retry succeeded.
- **HTTPS (apt.omaxian.org):** InRelease/keyring identical to repo-local, gpgv Good signature; all 8 Filename URLs 200; isolated `apt-get update` clean (0 W/E), candidates match; voxtype absent.
- **ISOs (s3://omaxian-iso/releases/0.1/), verified via re-download sha256 + download.omaxian.org Content-Length:**
  - base: 3098339328 bytes, sha256 `7b1bf01cd0df7e692714a16958fa8e414e00a5ce123bd7e8022af328061ecb7d` ✔
  - full: 9389113344 bytes, sha256 `88c29b28b4e07034d96161a6219da7f28f3cd795b9b2b491cc5aed3776b88d99` ✔
  - `.sha256` files identical to local.
- No website PR.
