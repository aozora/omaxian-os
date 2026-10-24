# TODO: netinstall ISO

Not built yet. Plan:
- A tiny ISO (~150 MB): kernel + initrd + a minimal squashfs (base 00-list +
  Calamares) and no desktop payload.
- Calamares `netinstall` module with groups made from config/package-lists
  (Omaxian desktop, XFCE, user apps, games/OpenRA), and a `packages` step that
  runs `apt-get install` against packages.devuan.org + apt.omaxian.org + xlibre.
- Or a debootstrap-style installer: Calamares runs mmdebstrap into the target
  (shellprocess), then the same configure steps as build-rootfs.sh
  (`s_configure`), which should move into a shared `omaxian-configure` script
  inside omaxian-base.
- Needs apt.omaxian.org live, signed with the real key first.
