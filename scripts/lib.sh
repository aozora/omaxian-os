# shellcheck shell=bash
# Common helpers for the Omaxian OS build scripts.
set -euo pipefail
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config/build.conf
. "$_LIB_DIR/../config/build.conf"
msg()  { printf '\033[1;36m:: %s\033[0m\n' "$*" >&2; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mxx %s\033[0m\n' "$*" >&2; exit 1; }
need() { local t; for t; do command -v "$t" >/dev/null || die "missing build tool: $t"; done; }
# read a package list (strip comments/blank lines)
read_list() { grep -hvE '^\s*(#|$)' "$@" | sed 's/\s*#.*//' | tr -s ' \t' '\n' | grep -v '^$'; }
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
mkdir -p "$BUILDDIR" "$OUTDIR"
