#!/bin/bash
# Build docs/package-sources-<version>.md from a rootfs (preferred: apt lists
# still present, so each package's origin suite is known) or from a
# dpkg-query -W packages file plus config/pins (no invented origins).
#
#   package-sources.sh [--rootfs DIR] [--packages FILE] [--lists DIR] [--flavor base|full]
#                      [--community-apps DIR] [--out FILE] [--docs-only]
#                      [--version V]
#
# Default --out is $OUTDIR/package-sources-<version>.md and a copy at
# $TOPDIR/docs/package-sources-<version>.md (skipped with --out FILE alone;
# --docs also writes the docs/ copy).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../config/build.conf
. "$HERE/../config/build.conf"

ROOTFS=""; PKGS_FILE=""; FLAVOR=""; COMM_APPS=""; OUT=""; WRITE_DOCS=1; VER=$OMAXIAN_VERSION; LISTS_OPT=""
usage() { sed -n '2,16p' "$0" | sed 's/^# \?//'; exit 2; }
while [ $# -gt 0 ]; do
	case $1 in
		--rootfs) ROOTFS=$2; shift 2 ;;
		--packages) PKGS_FILE=$2; shift 2 ;;
		--lists) LISTS_OPT=$2; shift 2 ;;
		--flavor) FLAVOR=$2; shift 2 ;;
		--community-apps) COMM_APPS=$2; shift 2 ;;
		--out) OUT=$2; WRITE_DOCS=0; shift 2 ;;
		--docs) WRITE_DOCS=1; shift ;;
		--docs-only) WRITE_DOCS=1; shift ;;
		--version) VER=$2; shift 2 ;;
		-h|--help) usage ;;
		*) echo "unknown option: $1" >&2; usage ;;
	esac
done

if [ -z "$ROOTFS" ] && [ -z "$PKGS_FILE" ]; then
	# Prefer a built rootfs (lists may already be gone); fall back to OUTDIR.
	for c in full base; do
		if [ -d "$BUILDDIR/rootfs-$c" ] && [ -f "$BUILDDIR/rootfs-$c/var/lib/dpkg/status" ]; then
			ROOTFS=$BUILDDIR/rootfs-$c; FLAVOR=${FLAVOR:-$c}; break
		fi
	done
	if [ -z "$ROOTFS" ]; then
		for c in full base; do
			if [ -f "$OUTDIR/omaxian-$c.packages" ]; then
				PKGS_FILE=$OUTDIR/omaxian-$c.packages; FLAVOR=${FLAVOR:-$c}; break
			fi
		done
	fi
fi
if [ -z "$ROOTFS" ] && [ -z "$PKGS_FILE" ]; then
	echo "xx package-sources: no rootfs or --packages file (build the rootfs, or pass a dpkg-query -W listing)" >&2
	exit 2
fi

if [ -z "$FLAVOR" ]; then
	if [ -n "$ROOTFS" ] && [ -e "$ROOTFS/var/lib/omaxian/full-offline" ]; then FLAVOR=full
	else FLAVOR=base; fi
fi

if [ -z "$COMM_APPS" ]; then
	for d in "$BUILDDIR/src/omaxian/community-apps" "$TOPDIR/build/src/omaxian/community-apps"; do
		if [ -d "$d" ]; then COMM_APPS=$d; break; fi
	done
fi

if [ -z "$OUT" ]; then
	mkdir -p "$OUTDIR"
	OUT=$OUTDIR/package-sources-$VER.md
	WRITE_DOCS=1
fi

# Collect package\tversion (and optional \torigin) into a temp file.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LIST=$TMP/packages.tsv   # pkg \t version
: > "$LIST"

if [ -n "$ROOTFS" ]; then
	if [ -f "$ROOTFS/var/lib/dpkg/status" ]; then
		dpkg-query --admindir="$ROOTFS/var/lib/dpkg" -W -f '${Package}\t${Version}\n' > "$LIST"
	else
		echo "xx package-sources: $ROOTFS has no /var/lib/dpkg/status" >&2
		exit 1
	fi
else
	# Accept "pkg\tver" or "pkg ver"
	awk -F '[\t ]+' 'NF>=2 && $1 !~ /^#/ {print $1 "\t" $2}' "$PKGS_FILE" > "$LIST"
fi

# Origin map: pkg\tver -> label, when apt lists are present.
ORIGIN_TSV=$TMP/origin.tsv
: > "$ORIGIN_TSV"
LISTS=""
if [ -n "$LISTS_OPT" ]; then
	LISTS=$LISTS_OPT
elif [ -n "$ROOTFS" ] && [ -d "$ROOTFS/var/lib/apt/lists" ]; then
	LISTS=$ROOTFS/var/lib/apt/lists
fi

# Pin metadata (no invented hashes: only values from config or pin files).
PINS=$TMP/pins.md
{
	echo "- **Omaxian shell**: \`$OMAXIAN_SHELL_REPO\` tag \`$OMAXIAN_SHELL_REF\` commit \`$OMAXIAN_SHELL_COMMIT\` (scripts/fetch-omaxian.sh verifies the tag, that the commit is on main, and that \`version\` matches)."
	echo "- **Nerd Fonts** JetBrainsMono: \`https://github.com/$NERD_FONTS_REPO/releases/download/v$NERD_FONTS_VERSION/JetBrainsMono.tar.xz\` sha256 \`$NERD_FONTS_JBM_SHA256\` (package omaxian-fonts-nerd $NERD_FONTS_VERSION-1)."
	echo "- **ydotool** source: \`https://github.com/$YDOTOOL_REPO/archive/refs/tags/v$YDOTOOL_VERSION.tar.gz\` sha256 \`$YDOTOOL_SRC_SHA256\`, commit \`$YDOTOOL_COMMIT\` (package omaxian-ydotool $YDOTOOL_VERSION-1)."
	echo "- **Strata** $STRATA_VERSION: \`https://github.com/$STRATA_REPO/releases/download/v$STRATA_VERSION/strata-$STRATA_VERSION-x86_64-unknown-linux-gnu.tar.gz\`. sha256 is taken from the Ed25519-signed release manifest at fetch time (scripts/fetch-strata.sh); it is not stored in this repo."
	# If a previous fetch recorded the hash, include it.
	if [ -f "$BUILDDIR/dl/strata-$STRATA_VERSION/.sha256" ]; then
		echo "  Recorded sha256 from the last fetch: \`$(cat "$BUILDDIR/dl/strata-$STRATA_VERSION/.sha256")\`."
	fi
	echo "- **VoxType** (full ISO optional pool only, not a default-installed package): \`https://github.com/$VOXTYPE_REPO/releases/download/v$VOXTYPE_VERSION/voxtype_${VOXTYPE_VERSION}-${VOXTYPE_DEB_REV}_amd64.deb\` sha256 \`$VOXTYPE_DEB_SHA256\`, signed by \`$VOXTYPE_SIGNING_FPR\` (plus omaxian-voxtype, ISO payload)."
} > "$PINS"

COMM_MD=$TMP/community.md
: > "$COMM_MD"
if [ -n "$COMM_APPS" ]; then
	{
		echo
		echo "Each app's \`.omaxian-prebuilt\` at the shell tag above:"
		echo
		echo "| App | URL | SHA-256 | tree | bin |"
		echo "|---|---|---|---|---|"
		for m in "$COMM_APPS"/*/.omaxian-prebuilt; do
			[ -f "$m" ] || continue
			app=$(basename "$(dirname "$m")")
			url=$(awk -F= '$1=="url"{sub(/^[^=]*=/,"");print}' "$m")
			sha=$(awk -F= '$1=="sha256"{print $2}' "$m")
			tree=$(awk -F= '$1=="tree"{print $2}' "$m")
			bin=$(awk -F= '$1=="bin"{print $2}' "$m")
			printf '| %s | %s | `%s` | `%s` | `%s` |\n' "$app" "$url" "$sha" "$tree" "$bin"
		done
	} > "$COMM_MD"
else
	printf '\nCommunity-app `.omaxian-prebuilt` pins were not available (no `build/src/omaxian/community-apps` and no `--community-apps`). They live in the Omaxian shell tree at the commit above; the next ISO build will include the table.\n' > "$COMM_MD"
fi

# Optional extras from a full rootfs (Flatpaks, payload AppImages) — only if present.
EXTRAS=$TMP/extras.md
: > "$EXTRAS"
if [ -n "$ROOTFS" ] && [ "$FLAVOR" = full ]; then
	{
		if [ -d "$ROOTFS/var/lib/flatpak/app" ]; then
			echo
			echo "### Full ISO: system Flatpaks (preinstalled)"
			echo
			echo '```'
			ls -1 "$ROOTFS/var/lib/flatpak/app" 2>/dev/null || true
			echo '```'
		fi
		if [ -d "$ROOTFS/usr/share/omaxian/payload/appimages" ]; then
			echo
			echo "### Full ISO: payload AppImages"
			echo
			echo '```'
			ls -1 "$ROOTFS/usr/share/omaxian/payload/appimages" 2>/dev/null || true
			echo '```'
		fi
	} > "$EXTRAS"
fi

# How origins were determined (honest).
METHOD=$TMP/method.txt
if [ -n "$LISTS" ] && compgen -G "$LISTS/*_Packages" >/dev/null; then
	echo "apt-lists" > "$METHOD"
else
	echo "inferred" > "$METHOD"
fi

XLIBRE_URI_VAL=$XLIBRE_URI
OMAXIAN_APT_VAL=$OMAXIAN_APT_URI
DEVUAN_MIRROR_VAL=$DEVUAN_MIRROR
CODENAME=$OMAXIAN_CODENAME
export LIST ORIGIN_TSV LISTS METHOD VER CODENAME FLAVOR XLIBRE_URI_VAL OMAXIAN_APT_VAL DEVUAN_MIRROR_VAL
export PINS COMM_MD EXTRAS OUT DEVUAN_SUITE

python3 - "$LIST" "$LISTS" "$METHOD" "$PINS" "$COMM_MD" "$EXTRAS" "$OUT" "$VER" "$CODENAME" "$FLAVOR" "$XLIBRE_URI_VAL" "$OMAXIAN_APT_VAL" "$DEVUAN_MIRROR_VAL" <<'PY'
import os, re, sys, pathlib, datetime, collections

list_path, lists_dir, method_path, pins_path, comm_path, extras_path, out_path, ver, codename, flavor, xlibre_uri, omaxian_apt, devuan_mirror = sys.argv[1:]
method = pathlib.Path(method_path).read_text().strip()
packages = []
with open(list_path) as f:
    for line in f:
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        pkg, ver_, *rest = line.split("\t")
        packages.append((pkg, ver_))

def label_from_list_filename(name: str):
    n = name
    # apt list files look like: host_path_dists_<suite>_<component>_binary-amd64_Packages
    if re.search(r"excalibur-backports", n):
        return "Devuan excalibur-backports"
    if re.search(r"excalibur-security", n):
        return "Devuan excalibur-security"
    if re.search(r"excalibur-updates", n):
        return "Devuan excalibur-updates"
    if re.search(r"excalibur", n) and "backports" not in n:
        # main/contrib/non-free from the merged Devuan repo
        return "Devuan excalibur"
    if "apt.omaxian.org" in n or re.search(r"127\.0\.0\.1[:_]8098", n) or "omaxian-build" in n or "omaxian_build" in n:
        return f"apt.omaxian.org ({omaxian_apt})"
    if "xlibre" in n.lower():
        return f"XLibre ({xlibre_uri})"
    if "brave" in n.lower():
        return "Brave apt (extrepo brave_release)"
    if "librewolf" in n.lower():
        return "LibreWolf apt (extrepo librewolf)"
    return None

# Index apt lists: (pkg, version) -> origin. Later files don't override an
# already-seen exact version (first match is enough; all lists with that
# version should agree on the suite).
origin = {}
if method == "apt-lists" and lists_dir and os.path.isdir(lists_dir):
    for fn in sorted(os.listdir(lists_dir)):
        if not fn.endswith("_Packages") and not fn.endswith("_Packages.xz") and not fn.endswith("_Packages.gz"):
            # uncompressed only — live-build/apt leaves *_Packages plain during a build
            continue
        path = os.path.join(lists_dir, fn)
        if not os.path.isfile(path):
            continue
        lab = label_from_list_filename(fn)
        if not lab:
            lab = f"apt list {fn}"
        try:
            text = open(path, "r", errors="replace").read()
        except OSError:
            continue
        current_pkg = None
        current_ver = None
        for line in text.splitlines():
            if line.startswith("Package: "):
                current_pkg = line[9:].strip()
                current_ver = None
            elif line.startswith("Version: "):
                current_ver = line[9:].strip()
                if current_pkg and current_ver and (current_pkg, current_ver) not in origin:
                    origin[(current_pkg, current_ver)] = lab
            elif line == "":
                current_pkg = current_ver = None

def infer(pkg: str, ver_: str) -> str:
    """Best-effort origin when apt lists are gone. Never invent a suite."""
    if pkg.startswith("omaxian-"):
        return f"apt.omaxian.org ({omaxian_apt})"
    if pkg.startswith("xserver-xlibre") or pkg.startswith("xlibre") or pkg in ("xlibre-archive-keyring", "xlibre-x11-common"):
        return f"XLibre ({xlibre_uri})"
    if pkg in ("brave-browser", "brave-keyring") or pkg.startswith("brave-"):
        return "Brave apt (extrepo brave_release)"
    if pkg == "librewolf" or pkg.startswith("librewolf-"):
        return "LibreWolf apt (extrepo librewolf)"
    if "~bpo13+" in ver_ or "excalibur-backports" in ver_:
        return "Devuan excalibur-backports (from version suffix ~bpo13+)"
    return "Devuan excalibur family (main/updates/security not distinguished; no apt policy)"

rows = []
for pkg, ver_ in packages:
    if method == "apt-lists" and (pkg, ver_) in origin:
        src = origin[(pkg, ver_)]
        how = "apt lists"
    elif method == "apt-lists":
        # installed but not in any current list: fall back, labelled as such
        src = infer(pkg, ver_) + " [not in residual apt lists]"
        how = "inferred"
    else:
        src = infer(pkg, ver_)
        how = "inferred"
    rows.append((src, pkg, ver_, how))

# Group by origin, stable package order
groups = collections.OrderedDict()
# Preferred section order
prefer = [
    "apt.omaxian.org",
    "Devuan excalibur-backports",
    "Devuan excalibur-security",
    "Devuan excalibur-updates",
    "Devuan excalibur",
    "XLibre",
    "Brave",
    "LibreWolf",
]
def section_key(label: str):
    for i, p in enumerate(prefer):
        if label.startswith(p):
            return (i, label)
    return (len(prefer), label)

rows.sort(key=lambda r: (section_key(r[0]), r[1]))
for src, pkg, ver_, how in rows:
    groups.setdefault(src, []).append((pkg, ver_, how))

now = datetime.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
pins = pathlib.Path(pins_path).read_text()
comm = pathlib.Path(comm_path).read_text()
extras = pathlib.Path(extras_path).read_text()

if method == "apt-lists":
    how_doc = (
        f"Origins were read from the rootfs apt lists under `/var/lib/apt/lists` "
        f"(exact suite: excalibur, excalibur-updates, excalibur-security, excalibur-backports, "
        f"plus third-party lists). The local build repo is recorded as `{omaxian_apt}` "
        f"(that is the origin shipped in the image)."
    )
else:
    how_doc = (
        "No apt lists were available (a dpkg name+version listing was used). "
        "Origins below are **inferred**, not claimed from `apt-cache policy`: "
        "`omaxian-*` → apt.omaxian.org; `xlibre*` / `xserver-xlibre*` → the XLibre URI in "
        "config/build.conf; `brave-*` / `librewolf*` → extrepo; versions containing "
        "`~bpo13+` → excalibur-backports; everything else is the Devuan excalibur family "
        "(main, updates and security are **not** distinguished). "
        "A later ISO build, which runs this script before apt lists are deleted, will replace "
        "the inferred column with exact suites."
    )

lines = []
a = lines.append
a(f"# Omaxian OS {ver} \"{codename}\" — package sources")
a("")
a(f"Generated {now} for the **{flavor}** image (dpkg set).")
a("")
a(how_doc)
a("")
a(f"Installed packages listed: **{len(packages)}**. Devuan mirror in the image: `{devuan_mirror}` (suites `{os.environ.get('DEVUAN_SUITE','excalibur')}` plus updates, security and backports).")
a("")
a("## Pinned / vendored downloads")
a("")
a(pins.rstrip())
a(comm.rstrip())
a("")

# Count inferred vs lists
n_lists = sum(1 for _s, _p, _v, h in rows if h == "apt lists")
n_inf = len(rows) - n_lists
if method == "apt-lists":
    a(f"Of {len(rows)} packages, {n_lists} were matched to an apt list; {n_inf} were not in residual lists and used the fallback.")
    a("")

for src, items in groups.items():
    a(f"## {src}")
    a("")
    a(f"{len(items)} packages.")
    a("")
    a("| Package | Version |")
    a("|---|---|")
    for pkg, ver_, _how in items:
        a(f"| `{pkg}` | `{ver_}` |")
    a("")

if extras.strip():
    a("## Image extras (not dpkg)")
    a(extras.rstrip())
    a("")

pathlib.Path(out_path).parent.mkdir(parents=True, exist_ok=True)
pathlib.Path(out_path).write_text("\n".join(lines) + "\n")
print(f"wrote {out_path} ({len(packages)} packages, {len(groups)} origin groups)", file=sys.stderr)
PY

if [ "$WRITE_DOCS" = 1 ]; then
	mkdir -p "$TOPDIR/docs"
	cp "$OUT" "$TOPDIR/docs/package-sources-$VER.md"
	echo ":: also $TOPDIR/docs/package-sources-$VER.md" >&2
fi
