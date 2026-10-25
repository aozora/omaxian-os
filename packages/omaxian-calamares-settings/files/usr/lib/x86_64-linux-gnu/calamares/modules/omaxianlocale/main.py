#!/usr/bin/env python3
# Omaxian OS: runs right before localecfg.
#
# Calamares 3.3 guesses the formats (LC_*) from the time zone's country, so
# English (US) + Europe/Rome showed "numbers and dates: italiano" and installed
# it_IT formats. On the live system /usr/share/i18n/SUPPORTED also lists bare
# language tags ("en UTF-8", diverted by this package), which Calamares prefers
# for its automatic guess: the formats then show the chosen language and are
# stored as the bare tag (e.g. "en"). This job turns every bare tag back into
# LANG before localecfg writes /etc/default/locale and runs locale-gen. A
# locale picked with "Change..." on the Locale page is always a full name
# (it_IT.UTF-8, en_GB.UTF-8, ...) and is kept as it is.
import re
import libcalamares

BARE = re.compile(r"^[a-z]{2,3}$")
SUPPORTED = ("/usr/share/i18n/SUPPORTED.omaxian-orig", "/usr/share/i18n/SUPPORTED")


def pretty_name():
    return "Setting the formats locale"


def full_locale(tag, supported=None):
    """A UTF-8 locale for language @p tag from the (original) SUPPORTED list:
    tag_TAG (it_IT, de_DE) or en_US for en, else the first one listed."""
    names = []
    for path in supported or SUPPORTED:
        try:
            with open(path) as f:
                names = [l.split()[0] for l in f if l.split() and "UTF-8" in l]
            break
        except OSError:
            continue
    own = [n for n in names if n.startswith(tag + "_")]
    pref = {"en": "en_US"}.get(tag, tag + "_" + tag.upper())
    for n in own:
        if n.split(".")[0] == pref:
            return n
    return own[0] if own else "en_US.UTF-8"


def fix(conf, supported=None):
    """Return a copy of the localeConf map with bare language tags replaced by LANG."""
    conf = dict(conf or {})
    lang = conf.get("LANG") or "en_US.UTF-8"
    if BARE.match(lang):  # never expected (Calamares prefers lang_CC), but stay valid
        lang = full_locale(lang, supported)
    conf["LANG"] = lang
    for key, value in list(conf.items()):
        if key.startswith("LC_") and (not value or BARE.match(str(value))):
            conf[key] = lang
    return conf


def run():
    gs = libcalamares.globalstorage
    old = gs.value("localeConf")
    new = fix(old)
    if new != old:
        libcalamares.utils.debug("omaxianlocale: {!s} -> {!s}".format(old, new))
        gs.insert("localeConf", new)
    return None
