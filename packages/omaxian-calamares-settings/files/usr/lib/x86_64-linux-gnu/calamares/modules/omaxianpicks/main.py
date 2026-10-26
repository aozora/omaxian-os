#!/usr/bin/env python3
# Omaxian OS: runs right before the packages module.
# Calamares' netinstall page only knows packages, and (3.3.x) ignores
# pre-/post-install scripts on package entries, so the picks that are not
# apt packages are written into netinstall.conf as marker "package" names
# (scripts/gen-netinstall.sh):
#     omaxian-pick:flatpak:<app-id>    optional Flatpak (e.g. Telegram)
#     omaxian-pick:appimage:<id>       "Extra apps (downloaded after install)"
# This job records the selected markers in the target
#     /var/lib/omaxian/optional-flatpaks.list
#     /var/lib/omaxian/optional-appimages.list
# (both always created, even empty: "none picked" differs from "no record")
# and removes the markers from packageOperations so apt never sees them.
# omaxian-firstboot acts on the records (install/remove Flatpaks, download
# the picked AppImages once online).
import os
import re
import libcalamares

PREFIX = "omaxian-pick:"
KINDS = {"flatpak": "optional-flatpaks.list", "appimage": "optional-appimages.list"}
ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")

def pretty_name():
    return "Recording optional Flatpaks and extra apps"

def _pkgname(p):
    return p if isinstance(p, str) else (p.get("package") or p.get("name") or "")

def split_ops(ops):
    """Return (new_ops, picks{kind: [ids]}, bad[markers])."""
    picks = {k: [] for k in KINDS}
    bad = []
    out = []
    for op in ops or []:
        new = {}
        for key, val in op.items():
            if not isinstance(val, list):
                new[key] = val
                continue
            keep = []
            for p in val:
                name = _pkgname(p)
                if not name.startswith(PREFIX):
                    keep.append(p)
                    continue
                parts = name[len(PREFIX):].split(":", 1)
                if len(parts) == 2 and parts[0] in KINDS and ID_RE.match(parts[1]):
                    if parts[1] not in picks[parts[0]]:
                        picks[parts[0]].append(parts[1])
                else:
                    bad.append(name)
            if keep:
                new[key] = keep
        if any(k != "source" for k in new):
            out.append(new)
    return out, picks, bad

def record(root, picks):
    state = os.path.join(root, "var/lib/omaxian")
    os.makedirs(state, exist_ok=True)
    for kind, fname in KINDS.items():
        path = os.path.join(state, fname)
        old = []
        if os.path.exists(path):
            with open(path) as f:
                old = [l.strip() for l in f if l.strip()]
        with open(path, "w") as f:
            f.write("".join(i + "\n" for i in old + [i for i in picks[kind] if i not in old]))

def run():
    root = libcalamares.globalstorage.value("rootMountPoint")
    if not root:
        return ("No root mount point", "rootMountPoint is not set")
    gs = libcalamares.globalstorage
    ops = gs.value("packageOperations") if gs.contains("packageOperations") else []
    new, picks, bad = split_ops(ops)
    if bad:
        libcalamares.utils.warning("omaxian picks: ignoring malformed markers %s" % bad)
    record(root, picks)
    gs.insert("packageOperations", new)
    libcalamares.utils.debug("omaxian picks: %s" % picks)
    return None
