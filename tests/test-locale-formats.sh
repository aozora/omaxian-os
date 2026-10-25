#!/bin/bash
# Formats (LC_*) follow the installer language unless changed on the Locale page.
# Unit tests: omaxianlocale job (fake libcalamares), calamares-locale-formats
# (fake target roots), SUPPORTED bare-tag generation (postinst), settings.conf order.
set -u
cd "$(dirname "$0")/.."
P=packages/omaxian-calamares-settings; C=$P/files
S=$C/usr/libexec/omaxian/calamares-locale-formats
SUP=/usr/share/i18n/SUPPORTED; [ -r $SUP ] || SUP=build/rootfs-base/usr/share/i18n/SUPPORTED
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
LCS="LC_NUMERIC LC_TIME LC_MONETARY LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION"

# 1) omaxianlocale job on Calamares' localeConf
T=$(mktemp -d); mkdir -p $T/lib
cat > $T/lib/libcalamares.py <<'PY'
class _GS(dict):
    def value(self, k): return self.get(k)
    def insert(self, k, v): self[k] = v
globalstorage = _GS()
class utils:
    @staticmethod
    def debug(*a): pass
PY
PYTHONPATH=$T/lib:$C/usr/lib/x86_64-linux-gnu/calamares/modules/omaxianlocale SUP=$SUP python3 - <<'PY' || fail=1
import os, libcalamares as lc, main
main.SUPPORTED = (os.environ["SUP"],)
LCS = "LC_NUMERIC LC_TIME LC_MONETARY LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION".split()
def conf(lang, fmt): d = {"LANG": lang}; d.update({k: fmt for k in LCS}); return d
cases = [
  ("auto formats 'en' (English US, Europe/Rome) -> en_US", conf("en_US.UTF-8", "en"), "en_US.UTF-8", "en_US.UTF-8"),
  ("auto formats 'it' (Italian, America/New_York) -> it_IT", conf("it_IT.UTF-8", "it"), "it_IT.UTF-8", "it_IT.UTF-8"),
  ("explicit it_IT with English kept",  conf("en_US.UTF-8", "it_IT.UTF-8"), "en_US.UTF-8", "it_IT.UTF-8"),
  ("explicit en_GB kept",               conf("en_US.UTF-8", "en_GB.UTF-8"), "en_US.UTF-8", "en_GB.UTF-8"),
  ("empty LC -> LANG",                  conf("de_DE.UTF-8", ""), "de_DE.UTF-8", "de_DE.UTF-8"),
  ("bare LANG resolved to a full locale", conf("it", "it"), "it_IT.UTF-8", "it_IT.UTF-8"),
]
bad = 0
for name, c, lang, fmt in cases:
    lc.globalstorage.clear(); lc.globalstorage.insert("localeConf", c)
    main.run(); got = lc.globalstorage.value("localeConf")
    if got["LANG"] == lang and all(got[k] == fmt for k in LCS): print("ok   job:", name)
    else: print("FAIL job:", name, got); bad = 1
lc.globalstorage.clear(); main.run()
g = lc.globalstorage.value("localeConf")
if g and g.get("LANG") == "en_US.UTF-8": print("ok   job: no localeConf -> LANG en_US")
else: print("FAIL job: no localeConf", g); bad = 1
raise SystemExit(bad)
PY
rm -rf $T

# 2) calamares-locale-formats safety net on the target files
check() { # name lang formats expected
	d=$(mktemp -d); mkdir -p $d/etc/default
	{ echo "LANG=$2"; for k in $LCS; do echo "$k=$3"; done; } > $d/etc/default/locale; cp $d/etc/default/locale $d/etc/locale.conf
	sh $S "$d"; r=0
	for f in etc/default/locale etc/locale.conf; do
		[ "$(grep -c "^LC_.*=$4\$" $d/$f)" = 9 ] && [ "$(sed -n 's/^LANG=//p' $d/$f)" = "$2" ] || r=1
	done
	[ $r = 0 ] && ok "post: $1" || bad "post: $1 ($(tr '\n' ' ' < $d/etc/default/locale))"; rm -rf "$d"
}
check "bare 'en' -> en_US"            en_US.UTF-8 en          en_US.UTF-8
check "explicit it_IT with English kept" en_US.UTF-8 it_IT.UTF-8 it_IT.UTF-8
check "explicit en_GB kept"           en_US.UTF-8 en_GB.UTF-8 en_GB.UTF-8
check "it_IT unchanged"               it_IT.UTF-8 it_IT.UTF-8 it_IT.UTF-8

# 3) postinst: SUPPORTED + one bare tag per language; Calamares' parser
#    (UTF-8 lines, " UTF-8" chopped) then sees "en", "it", ...
gen=$(sed -n 's/^\([a-z][a-z][a-z]\?\)_[A-Z].*UTF-8$/\1 UTF-8/p' $SUP | sort -u)
for t in en it de fr; do echo "$gen" | grep -qx "$t UTF-8" || bad "postinst tag $t"; done
grep -q 'sed -n .s/^\\(\[a-z\]\[a-z\]\[a-z\]\\?\\)_\[A-Z\].\*UTF-8\$/\\1 UTF-8/p' $P/debian/postinst && ok "postinst generates bare tags ($(echo "$gen" | wc -l) languages)" || bad "postinst sed differs from the test"
grep -q -- '--remove' $P/debian/postrm && ok "postrm removes the diversion" || bad "postrm"

# 5) Port of Calamares 3.3.14 loadLocales() + LocaleConfiguration::fromLanguageAndLocation()
#    on the SUPPORTED file as the postinst writes it: English (US) in Europe/Rome
#    must now give automatic formats "en" (was it_IT.UTF-8 with the stock file).
{ cat $SUP; echo "$gen"; } > /tmp/omx-supported.$$
SUP2=/tmp/omx-supported.$$ SUP=$SUP python3 - <<'PY' || fail=1
import os, re
def load(path):
    out = []
    for l in open(path).read().split("\n"):
        l = " ".join(l.split())
        if "UTF-8" not in l.upper() and "utf8" not in l.lower(): continue
        if l.endswith(" UTF-8"): l = l[:-6]
        out.append(l.strip())
    return out
RX = re.compile(r"^([a-zA-Z]+)(_[a-zA-Z]+)?(\.[-a-zA-Z0-9]+)?(@[a-zA-Z]+)?")
def parts(n):
    m = RX.match(n)
    if not m or not m.group(1): return None
    g = lambda i: (m.group(i) or "")[1:]
    return dict(lang=m.group(1), country=g(2), enc=g(3), region=g(4))
def name(p): return p["lang"] + ("_" + p["country"] if p["country"] else "") + ("." + p["enc"] if p["enc"] else "") + ("@" + p["region"] if p["region"] else "")
def sim(a, b):
    if not a or not b or a["lang"] != b["lang"]: return 0
    return 50 + (30 if a["region"] == b["region"] else 0) + ((10 if not a["country"] else 20) if a["country"] == b["country"] else 0) + (10 if a["country"] != b["country"] and not b["country"] else 0)
QLOC = {"en": "en_US", "it": "it_IT", "de": "de_DE"}
def best(lang, avail, cc):
    me = parts(lang); others = [parts(a) for a in avail]; bm = None
    for ref in (me, dict(me, country=cc), dict(me, country=QLOC.get(me["lang"], "")[3:])):
        cand = sorted([o for o in others if o], key=lambda o: sim(ref, o))[-1]
        sc = sim(ref, cand)
        if sc >= 100: return cand
        if sc > 0: bm = cand
    return bm or parts("en_US.UTF-8")
CDL = {"IT": "it", "US": "en", "DE": "de", "GB": "en", "FR": "fr"}
def formats(lang, avail, cc):
    b = best(lang, avail, cc); f = ""
    if b["lang"] in avail: f = b["lang"]
    elif b["lang"] + "_" + cc in avail: f = b["lang"] + "_" + cc
    if not f:
        av = sorted(l for l in avail if "_" + cc in l)
        if len(av) == 1: f = av[0]
        elif cc in CDL:
            f = next((l for l in avail if l.startswith(CDL[cc] + "_" + cc)), "")
    return name(b), f or name(b)
bad = 0
for label, path, lang, cc, want in [
    ("stock SUPPORTED: en_US + IT -> it_IT (the bug)", os.environ["SUP"], "en_US", "IT", ("en_US.UTF-8", "it_IT.UTF-8")),
    ("Omaxian SUPPORTED: en_US + IT -> en", os.environ["SUP2"], "en_US", "IT", ("en_US.UTF-8", "en")),
    ("Omaxian SUPPORTED: LANG 'en' + IT -> en_US.UTF-8 / en", os.environ["SUP2"], "en", "IT", ("en_US.UTF-8", "en")),
    ("Omaxian SUPPORTED: it_IT + US -> it", os.environ["SUP2"], "it_IT", "US", ("it_IT.UTF-8", "it")),
    ("Omaxian SUPPORTED: de_DE + IT -> de", os.environ["SUP2"], "de_DE", "IT", ("de_DE.UTF-8", "de")),
]:
    got = formats(lang, load(path), cc)
    if got == want: print("ok   calamares-port:", label)
    else: print("FAIL calamares-port:", label, got); bad = 1
raise SystemExit(bad)
PY
rm -f /tmp/omx-supported.$$

# 4) settings.conf: omaxianlocale right before localecfg; post hook still there
seq=$(sed -n '/^- exec:/,/^- show:/p' $C/etc/calamares/settings.conf)
n() { echo "$seq" | grep -n -- "- $1\$" | cut -d: -f1; }
[ "$(n omaxianlocale)" -eq $(( $(n localecfg) - 1 )) ] && [ "$(n locale)" -lt "$(n omaxianlocale)" ] && ok "exec: locale < omaxianlocale < localecfg" || bad "exec order"
grep -q calamares-locale-formats $C/usr/libexec/omaxian/calamares-post && ok "calamares-post safety net" || bad "calamares-post hook"
exit $fail
