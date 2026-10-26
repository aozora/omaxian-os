#!/usr/bin/env python3
# Omaxian OS: runs after the packages module.
#  - records the optional groups picked on the netinstall page
#    (/var/lib/omaxian/optional-packages.list) and the ones that could not be
#    installed now (offline base ISO) in optional-pending.list, which
#    omaxian-firstboot installs once the machine is online;
#  - drops the offline optional pool of the full ISO from the target.
#  - makes sure optional-flatpaks.list (Flatpak groups picked, Telegram)
#    exists, so omaxian-firstboot can tell "none picked" from "no record";
#  - same for optional-appimages.list (Extra apps picked; downloaded by
#    omaxian-firstboot once online);
# Packages listed in /etc/calamares/omaxian-offline-only.list (live system;
# full ISO only: VoxType, not in the Devuan/Omaxian archives) are never left
# pending: omaxian-firstboot could not install them and would retry forever.
import glob
import os
import subprocess
import libcalamares

def pretty_name():
    return "Recording optional applications"

# group entries that only record an optional Flatpak (scripts/gen-netinstall.sh):
# "flatpak" + post-install omaxian-optional-flatpak; not an optional package
FLATPAK_MARK = "omaxian-optional-flatpak"
# same for the optional AppImages ("Extra apps"): "curl" + omaxian-optional-appimage
APPIMAGE_MARK = "omaxian-optional-appimage"
MARKS = (FLATPAK_MARK, APPIMAGE_MARK)

def _names(ops):
    out = []
    for op in ops or []:
        for key in ("install", "try_install"):
            for p in op.get(key, []) or []:
                if not isinstance(p, str) and any(m in (p.get("post-script") or "") for m in MARKS):
                    continue
                name = p if isinstance(p, str) else (p.get("package") or p.get("name"))
                if name and name not in out:
                    out.append(name)
    return out

def _installed(root, pkg):
    r = subprocess.run(["chroot", root, "dpkg-query", "-W", "-f=${db:Status-Status}", pkg],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    return r.returncode == 0 and r.stdout.strip() == "installed"

OFFLINE_ONLY = "/etc/calamares/omaxian-offline-only.list"

def _offline_only(path=None):
    path = path or OFFLINE_ONLY
    try:
        with open(path) as f:
            return {l.strip() for l in f if l.strip() and not l.lstrip().startswith("#")}
    except FileNotFoundError:
        return set()

def run():
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        return ("No root mount point", "rootMountPoint is not set")
    wanted = _names(libcalamares.globalstorage.value("packageOperations"))
    state = os.path.join(root, "var/lib/omaxian")
    os.makedirs(state, exist_ok=True)
    missing = [p for p in wanted if not _installed(root, p)]
    only = _offline_only()
    pending = [p for p in missing if p not in only]
    dropped = [p for p in missing if p in only]
    if dropped:
        libcalamares.utils.warning("omaxian optional: not installed and only available "
                                   "offline on the full ISO (not retried): %s" % dropped)
    # optional Flatpaks: the picked ones were appended by omaxian-optional-flatpak
    # during the packages module; make sure the record exists (even if empty)
    # so omaxian-firstboot knows the pick was made (full ISO: removes the others)
    open(os.path.join(state, "optional-flatpaks.list"), "a").close()
    # optional AppImages: same, recorded by omaxian-optional-appimage
    open(os.path.join(state, "optional-appimages.list"), "a").close()
    with open(os.path.join(state, "optional-packages.list"), "w") as f:
        f.write("".join(p + "\n" for p in wanted))
    with open(os.path.join(state, "optional-pending.list"), "w") as f:
        f.write("".join(p + "\n" for p in pending))
    libcalamares.utils.debug("omaxian optional: selected=%s pending=%s" % (wanted, pending))
    # full ISO offline pool: only needed during the install
    for p in ("etc/apt/sources.list.d/omaxian-optional-pool.list",):
        try:
            os.remove(os.path.join(root, p))
        except FileNotFoundError:
            pass
    subprocess.run(["rm", "-rf", os.path.join(root, "var/cache/omaxian/optional-pool")]
                   + glob.glob(os.path.join(root, "var/lib/apt/lists/*optional-pool*")))
    return None
