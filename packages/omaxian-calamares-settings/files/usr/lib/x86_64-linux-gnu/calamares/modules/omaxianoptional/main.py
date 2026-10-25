#!/usr/bin/env python3
# Omaxian OS: runs after the packages module.
#  - records the optional groups picked on the netinstall page
#    (/var/lib/omaxian/optional-packages.list) and the ones that could not be
#    installed now (offline base ISO) in optional-pending.list, which
#    omaxian-firstboot installs once the machine is online;
#  - drops the offline optional pool of the full ISO from the target.
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

def run():
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        return ("No root mount point", "rootMountPoint is not set")
    wanted = _names(libcalamares.globalstorage.value("packageOperations"))
    state = os.path.join(root, "var/lib/omaxian")
    os.makedirs(state, exist_ok=True)
    pending = [p for p in wanted if not _installed(root, p)]
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
