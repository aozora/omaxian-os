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
