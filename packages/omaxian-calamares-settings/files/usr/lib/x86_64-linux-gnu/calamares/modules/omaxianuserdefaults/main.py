#!/usr/bin/env python3
# Omaxian OS: apply the per-user defaults picked in the installer to the new
# user (runs after the packages module; the helpers ship in omaxian-session,
# which stays installed):
#  - default file manager from the packagechooser@filemanager page
#    (GlobalStorage packagechooser_filemanager = strata|folio; default strata):
#    /etc/omaxian/file-manager (users created later get it at login) and the
#    user's ~/.config/mimeapps.list inode/directory entry, which the Omaxian
#    shell's omarchy-launch-files (Super+Shift+F) opens via xdg-mime.
#  - OnlyOffice: ~/.config/onlyoffice/DesktopEditors.conf [General]
#    titlebar=system merged into any existing file, owned by the user.
import libcalamares

CHOICES = ("strata", "folio")
DEFAULT = "strata"

def pretty_name():
    return "Applying the user's default applications"

def choice():
    gs = libcalamares.globalstorage
    keys = ["packagechooser_filemanager"] + [k for k in gs.keys() if str(k).startswith("packagechooser_")]
    for k in keys:
        if gs.contains(k):
            v = str(gs.value(k) or "").strip().lower()
            if v in CHOICES:
                return v
    return DEFAULT

def run():
    gs = libcalamares.globalstorage
    user = gs.value("username") if gs.contains("username") else None
    fm = choice()
    libcalamares.utils.debug("omaxian user defaults: file manager=%s user=%s" % (fm, user))
    rc = libcalamares.utils.target_env_call(["/usr/bin/omaxian-default-file-manager", "--system", fm])
    if rc != 0:
        libcalamares.utils.warning("omaxian-default-file-manager --system %s failed (%s)" % (fm, rc))
    if not user:
        libcalamares.utils.warning("omaxian user defaults: no username in GlobalStorage")
        return None
    for cmd in (["/usr/bin/omaxian-default-file-manager", "--user", user, fm],
                ["/usr/libexec/omaxian/onlyoffice-defaults", user]):
        rc = libcalamares.utils.target_env_call(cmd)
        if rc != 0:
            libcalamares.utils.warning("%s failed (%s)" % (" ".join(cmd), rc))
    return None
