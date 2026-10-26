# Packages from the brief that are missing, renamed or handled differently

| Requested | Status in Devuan 6 Excalibur | What Omaxian OS does |
|---|---|---|
| `cargo` | replaced on request | `rustup` (toolchains per user) |
| `fontmanager` | renamed | `font-manager` |
| `qemu-kvm` | virtual | `qemu-system-x86` |
| `witr` | not packaged anywhere in Debian/Devuan | left out; TODO: package from upstream into apt.omaxian.org |
| `xkb-switch` | not in excalibur | left out (Omaxian uses its own layout switcher) |
| `firefox`, `firefox-esr` | pinned -1 by policy | Brave + LibreWolf via extrepo |
| `systemd`, `pulseaudio`, `xserver-xorg-core` | pinned -1 | elogind, PipeWire, XLibre (`xserver-xlibre-core` *provides* `xserver-xorg-core`, so the -1 pin is on the real Xorg package only) |
| `ttf-mscorefonts-installer` | contrib, downloads fonts from SourceForge at install | EULA preseeded; with no network during the build the fonts are fetched later (`update-ms-fonts`) |
| Strata | not packaged upstream | `omaxian-strata` built from the signed GitHub release (Ed25519 manifest verified); portal + udiskie extras not packaged yet |
| Gear Lever | Flatpak only | `it.mijorus.gearlever` from Flathub |
| AppImages | not packages | config/appimages.manifest: 10 bundled (payload/appimages, full ISO) + 6 optional downloaded after install (installer group "Extra apps"), `omaxian-appimage-fetch` |
| default games | `gnome-games` etc. | apt pin -1 (`30-omaxian-nogames.pref`) + purge at build |
