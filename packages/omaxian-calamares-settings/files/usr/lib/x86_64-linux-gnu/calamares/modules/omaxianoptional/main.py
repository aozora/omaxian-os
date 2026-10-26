#!/usr/bin/env python3
# Omaxian OS: runs after the packages module.
#  - records the optional groups picked on the netinstall page
#    (/var/lib/omaxian/optional-packages.list) and the ones that could not be
#    installed now (offline base ISO) in optional-pending.list, which
#    omaxian-firstboot installs once the machine is online;
#  - drops the offline optional pool of the full ISO from the target.
# Packages listed in /etc/calamares/omaxian-offline-only.list (live system;
# full ISO only: VoxType, not in the Devuan/Omaxian archives) are never left
# pending: omaxian-firstboot could not install them and would retry forever.
import glob
import os
import subprocess
import libcalamares

def pretty_name():
    return "Recording optional applications"

def _names(ops):
    out = []
    for op in ops or []:
        for key in ("install", "try_install"):
            for p in op.get(key, []) or []:
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
