# VoxType voice dictation (full ISO only, optional group 7)

Decision (owner, 26 Oct 2026): **option B**. The unmodified upstream `.deb` ships in
the full ISO's offline pool, as the 7th Calamares Applications group "Voice dictation
(VoxType)". It is **unselected by default**. The base ISO doesn't offer the group at
all, because VoxType isn't in any online archive, so the base ISO keeps its 6 groups.

## Pin and verification (scripts/fetch-voxtype.sh)

- `config/build.conf` pins:
  - `VOXTYPE_VERSION=1.1.1`, `VOXTYPE_DEB_REV=1`;
  - `VOXTYPE_DEB_SHA256=1d4767ca…57ed3c`, the same as the GitHub asset digest;
  - `VOXTYPE_SIGNING_FPR=9CCF7915B750CAE8B095ED1AA3FC9F33FD209279`.
- The public release key is committed as `config/upstream-keys/voxtype-release.asc`.
  It is "Voxtype Release Signing <pete+voxtype-ci@peteonrails.com>", ed25519, expiring
  2030, and is identical on keys.openpgp.org and keyserver.ubuntu.com.
  **Trust on first use:** upstream doesn't publish the fingerprint in its docs or README.
- At fetch time the script:
  1. checks the sha256 pin, deleting the file on a mismatch;
  2. checks `voxtype_1.1.1-1_amd64.deb.asc`, which must give `VALIDSIG` by the pinned
     fingerprint;
  3. checks that `SHA256SUMS.txt` is signed by the same key. That file doesn't list the
     `.deb`, so the script also compares the avx2 and baseline binaries *inside* the
     `.deb` with the signed sums.
- gpg runs in a throwaway `--homedir`. Files are cached in `build/dl/voxtype-1.1.1/`,
  with an optional offline seed in `payload/voxtype/`. Both are gitignored, so no binary
  is committed.
- `tests/test-voxtype.sh` covers good, wrong sha, bad `.deb` signature, tampered sums
  and wrong signer.

## Packaging on Devuan / sysvinit

- **`voxtype` (upstream, unmodified).**
  - Depends: libasound2, libc6, curl (all in the base).
  - Recommends: pipewire-alsa (in the base), wtype and wl-clipboard. The last two are
    Wayland-only and deliberately left out of the pool. apt skips Recommends it can't
    find, so the offline install still completes. An online install may pull them; they
    are harmless on X11, where the output falls through to xclip.
  - Its postinst only prints hints (input group, `systemctl --user`). It changes nothing.
  - The shipped `/usr/lib/systemd/user/voxtype.service` stays inert, since there's no
    systemd.
  - About 690 MB installed (all backends, CUDA included). The pool grows by about
    376 MB.
- **`omaxian-voxtype` (ours, arch all, full pool only, not in the Omaxian apt repo).**
  - Depends: `voxtype (>= 1.1.1), xclip, libnotify-bin, procps`.
  - It diverts the upstream `/usr/bin/voxtype` to `/usr/bin/voxtype.upstream`. The
    upstream wrapper runs the AVX2 build on *any* CPU without AVX-512, which is SIGILL on
    older CPUs and many VMs. Ours picks avx512, avx2 (only with fma) or baseline, and
    `VOXTYPE_GPU=1` picks vulkan.
  - `omaxian-voxtype-toggle` works like this:
    - with no model yet, it opens a terminal on `voxtype setup model` (needs internet);
    - otherwise it starts `voxtype -q daemon --clipboard` per user on demand (setsid, no
      systemd);
    - then it runs `voxtype record toggle`.
  - `/etc/X11/Xsession.d/36omaxian-voxtype` seeds
    `~/.config/i3/config.d/60-voxtype.conf` once per user:
    `bindsym Mod4+Ctrl+v exec --no-startup-id /usr/bin/omaxian-voxtype-toggle`.
    Super+Ctrl+V was free. A deleted file is not re-created (marker
    `~/.local/state/omaxian/voxtype-i3-seeded`).
  - **The `input` group is never touched.** The upstream evdev hotkey stays disabled, as
    in the upstream default `/etc/voxtype/config.toml`, so no keylogger-capable group
    membership is needed. Typing at the cursor (ydotool, trixie-backports, root uinput
    daemon) or the evdev hotkey are opt-in steps for the user. See
    `/usr/share/doc/omaxian-voxtype/README.Omaxian`.

## Usage

1. Press Super+Ctrl+V. The first time, pick a model in the terminal (base.en is about
   142 MB, tiny.en about 75 MB). No model is on the ISO, so this needs internet.
2. Press Super+Ctrl+V again to start recording, and once more to stop. The text is put
   on the clipboard by xclip; paste it with Ctrl+V (Shift+Insert in terminals).

Manual alternative: run `voxtype daemon --clipboard &`, then `voxtype record start`
and `voxtype record stop`.

## Offline install and firstboot

- `config/optional-groups-full.list` holds the full-only group. The full rootfs build
  re-generates the live `/etc/calamares/modules/netinstall.conf` with
  `scripts/gen-netinstall.sh` from both lists, giving 7 groups. The base package keeps 6.
- The full build writes `/etc/calamares/omaxian-offline-only.list` (voxtype,
  omaxian-voxtype). If the job couldn't install a listed package, omaxianoptional logs a
  warning but never adds it to `optional-pending.list`. omaxian-firstboot can't install
  it from any archive and would otherwise retry forever. So the full ISO still writes
  `firstboot.done` offline.
- `s_optional_pool` copies both debs into the pool and downloads their archive
  dependencies without Recommends. It then **simulates** installing every group from the
  pool alone (`build/optional-pool-check.log`); the build fails if that doesn't resolve.

## Known limits

- The fingerprint is trust-on-first-use (see above).
- A speech model needs internet on first use.
- The daemon isn't stopped at logout. It's per user and exits with the X session's
  processes only if they are killed; otherwise `pkill -f 'voxtype-.* daemon'`.
- When VoxType is upgraded online, Omaxian's wrapper stays: the diversion keeps the new
  upstream wrapper as `voxtype.upstream`.
