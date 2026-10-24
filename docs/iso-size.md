# Why the base ISO is 3.5 GB, and how to shrink it

Measured on build/rootfs-base (2026-10-24): 2256 packages, about 8.5 GiB installed
(dpkg Installed-Size), 9.3 GiB on disk. The squashfs is about 3.4 GiB and the ISO 3.36 GiB
(3 521 845 248 bytes).

## Largest packages (installed size)
| MiB | package | where it comes from |
|---:|---|---|
| 477 | brave-browser | 40-user.list / extrepo |
| 471 | omaxian-session | vendored Omarchy + Omaxian (home-template 299M, src 178M) |
| 462 | librewolf | extrepo |
| 326 | fonts-noto-extra | Recommends chain (fonts-noto) |
| 316 | chromium (+65 chromium-common) | 40-user.list |
| 268 | thunderbird | 40-user.list |
| 210 | fonts-noto-cjk-extra | Recommends chain |
| 189 | firmware-iwlwifi | 10-base hardware firmware |
| 183 | papirus-icon-theme | desktop |
| 153 | linux-modules-7.2.9 | kernel |
| 129 | mesa-vulkan-drivers | desktop |
| 126 / 84 / 61 / 54 | buildah / podman / docker-compose / containernetworking-plugins | 40-user.list |
| 124 | libllvm19 | mesa |
| 113 | telegram-desktop | 40-user.list |
| 109 / 88+67 / 73 | inkscape / krita+krita-data / gimp-data | 40-user.list |
| 98 + 97 | libwebkit2gtk-4.1 + libwebkitgtk-6.0 | two webkit ABIs |
| 97 | firmware-amd-graphics | firmware |
| 89 + 70 + 42 | fonts-noto-cjk / -ui-extra / -core | fonts |
| 67 | qemu-system-x86 | 40-user.list |
| 67 | gcc-14 | build-essential / rustup |

Directory view: usr/share/fonts 881M, usr/share/locale 608M, usr/share/omaxian 477M,
/opt/brave.com 478M, usr/share/librewolf 463M, usr/share/icons 343M, usr/lib/firmware 344M,
/etc/skel 299M (a second copy of the Omarchy home template plus 164M of fonts), usr/share/doc 198M.

## Proposals (rough savings on the ISO, after xz)
1. **Split base and full properly.** Move chromium, thunderbird, gimp, inkscape, krita,
   telegram-desktop, the podman/buildah/docker-compose stack and qemu/libvirt to the full ISO.
   On base, install them at first boot or offer them in a "Install extras" menu. That's roughly
   2.0 GiB installed, about 700 to 800 MiB off the ISO. This is the biggest win.
2. **Ship only one extra browser on base.** Brave or LibreWolf, with the other at first boot:
   about 150 to 170 MiB.
3. **Fonts.** Use `--no-install-recommends` for fonts-noto, and drop fonts-noto-extra,
   fonts-noto-cjk-extra and fonts-noto-ui-extra. Keep fonts-noto-core and fonts-noto-cjk:
   about 600 MiB installed, 250 to 300 MiB off the ISO.
4. **Deduplicate the skel.** /etc/skel/.local duplicates usr/share/omaxian/home-template
   (omarchy 134M and fonts 164M). Make skel symlink or copy at first login
   (omaxian-firstboot already runs per user), and put the fonts in /usr/share/fonts/omaxian:
   about 300 MiB installed, around 120 MiB ISO.
5. **Strip docs, man pages and locales in the live image.** Use dpkg path-exclude in
   /etc/dpkg/dpkg.cfg.d/ for usr/share/doc (keep copyright), man and locale except en/it:
   about 700 MiB installed, around 200 MiB ISO.
6. **Drop omaxian-session's src/ copy** (178M of vendored Omarchy source, which is only
   needed at build time): around 60 MiB ISO.
7. **Firmware.** Keep it, since users expect wifi to work. Alternatively, ship
   firmware-iwlwifi only on full: about 60 MiB.
8. **Compression.** Use `mksquashfs -comp xz -Xbcj x86 -b 1M` (see build-iso.sh), or zstd

Points 1, 3, 4 and 5 together should bring the base ISO to about **1.8 to 2.0 GiB**.
