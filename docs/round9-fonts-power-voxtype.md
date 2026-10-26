# Round 9: JetBrains Mono Nerd Font, ACPI power button, VoxType evaluation

ISOs were **not** rebuilt in this round. Only the packages were rebuilt (`omaxian-fonts-nerd_3.5.1-1`, `omaxian-session_1.0.3-4`).

## JetBrains Mono Nerd Font (mandatory)

- **New package `omaxian-fonts-nerd` 3.5.1-1** (arch all). It ships 32 TTFs (`NerdFont` + `NerdFontMono` variants) in
  `/usr/share/fonts/truetype/jetbrains-mono-nerd/`, along with `OFL.txt` (uncompressed), a DEP-5 copyright (OFL-1.1) and
  `/etc/fonts/conf.d/56-omaxian-monospace.conf`. That file makes `monospace` resolve to *JetBrainsMono Nerd Font Mono*, then
  *JetBrainsMono Nerd Font*, then *JetBrains Mono*. postinst runs `fc-cache`.
- **Source:** the official `ryanoasis/nerd-fonts` release v3.5.1, `JetBrainsMono.tar.xz`, pinned in `config/build.conf`
  (`NERD_FONTS_VERSION`, `NERD_FONTS_JBM_SHA256`, `NERD_FONTS_JBM_VARIANTS`). It is fetched by
  `scripts/fetch-nerd-fonts.sh`, which verifies the pinned sha256 and cross-checks the upstream `SHA-256.txt`. The cache is
  `build/dl/`, and an optional offline seed can go in `payload/fonts/`. Both locations are gitignored, so no font binaries
  are committed.
  (The `officialrajdeepsingh/nerd-fonts-installer` script just downloads this same release interactively, so we use the
  release directly.)
- **Dependency:** `omaxian-session` now Depends on `omaxian-fonts-nerd`. The package is also listed in `50-omaxian.list`.
- **Size:** about +42 MB squashfs per ISO (80.5 MB installed, 7.2 MB deb). NerdFont-only would be about 21 MB.
- **Notes:** the home template still carries per-user nerd fonts as a harmless duplicate. The LightDM greeter keeps
  `JetBrains Mono 11`.
- **Test:** `tests/test-nerd-fonts.sh`.

## ACPI power button (omaxian-session 1.0.3-4)

- **Problem:** xfce4-power-manager defaults to `power-button-action=3` ("ask"). That needs the xfce4-session logout
  dialog, which is a no-op under i3. In xfpm's enum, 4 means shutdown.
- **Rejected approach:** diverting xfpm's `/etc/xdg/.../xfce4-power-manager.xml` conffile. A real dpkg test showed it is
  broken: when xfpm is installed first, our file is never installed, and purging our package deletes xfpm's file.
- **Fix:** `/usr/bin/omaxian-xfpm-defaults`, run at login from `/etc/X11/Xsession.d/36omaxian-xfpm` (before xfpm starts).
  It adds `power-button-action=4` to the user's xfconf channel **only if the user has not set a value**. It never runs as
  root, leaves unparseable files alone, and writes atomically.
  The live session's `37omaxian-live` also sets 4.
- **Verification:** real `xfconfd` in the built rootfs reads 4.
- **Test:** `tests/test-xfpm-power-button.sh`.

## VoxType (optional): not added; options for a decision

Findings (v0.6.x, voxtype.io / GitHub releases):

- **Upstream .deb:** 376 MB download, 687 MB installed (it bundles every backend, CUDA included). It needs glibc ≥ 2.39,
  its postinst assumes a systemd user service and the `input` group, and it is not in Debian/Devuan.
- **Models are separate downloads:** tiny.en about 75 MB, base.en 142 MB.
- **On X11/i3:**
  - Typing output needs `ydotool` (a root uinput daemon, systemd-oriented, only in trixie-backports) or `dotool` (not in
    Debian). `wtype` is Wayland-only.
  - Clipboard output works via `xclip`, which is already a session dependency.
  - The built-in hotkey needs evdev `input` group membership, which is keylogger-capable. An i3 `bindsym` calling
    `voxtype record start/stop` avoids that.
- **Integrity:** `SHA256SUMS.txt` plus a per-asset `.asc` (two signing keys), so pinning is possible.

Options:

- **A:** Package `omaxian-voxtype` from the pinned standalone binaries (avx2 + baseline, about 19 MB each, with a wrapper
  that selects by CPU flags). It would use clipboard mode, an i3 bindsym toggle and no `input` group, as a 7th optional
  Calamares group plus the full-ISO pool. About +15–40 MB, plus the model if bundled.
- **B:** Ship the upstream .deb in the full pool: +376 MB, with systemd/input-group assumptions.
- **C:** An online-only optional install from firstboot (nothing on the ISO).
- **D:** Skip for now.

Owner decisions needed: whether to bundle a model, clipboard vs ydotool typing, and whether to allow the `input` group.
