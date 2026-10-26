#!/bin/bash
# config/optional-groups.list -> Calamares netinstall.conf (local groups)
#   gen-netinstall.sh <optional-groups.list> <netinstall.conf> [more.list ...] [--appimages <appimages.manifest>]
# (the full ISO adds config/optional-groups-full.list; --appimages adds the
# "Extra apps (downloaded after install)" group: one unselected checkbox per
# class "optional" row of the manifest)
#   gen-netinstall.sh --optional-flatpaks <list> [more.list ...] <out>
# writes "group-id|app-id" lines (field 6) for omaxian-firstboot / the full build
set -eu
if [ "${1:-}" = --optional-flatpaks ]; then
	shift; out=${*: -1}; set -- "${@:1:$#-1}"
	{ echo "# GENERATED from config/optional-groups.list (field 6) by scripts/gen-netinstall.sh"
	  grep -hvE '^\s*(#|$)' "$@" | while IFS='|' read -r id name desc sel pkgs fps; do
		for f in $fps; do echo "$id|$f"; done; done; } > "$out"
	exit 0
fi
in=$1 out=$2; shift 2
lists=() manifest=""
while [ $# -gt 0 ]; do
	case "$1" in --appimages) manifest=$2; shift 2;; *) lists+=("$1"); shift;; esac
done
set -- "${lists[@]}"
{
cat <<'H'
---
# GENERATED from config/optional-groups.list by scripts/gen-netinstall.sh
groupsUrl: local
required: false
label:
    sidebar: "Applications"
    sidebar[it]: "Applicazioni"
    title: "Optional applications (installed from the network or the offline pool)"
    title[it]: "Applicazioni opzionali (installate dalla rete o dal pacchetto offline)"
groups:
H
grep -hvE '^\s*(#|$)' "$in" "$@" | while IFS='|' read -r id name desc sel pkgs fps; do
	printf '    - name: "%s"\n      description: "%s"\n      selected: %s\n      critical: false\n      hidden: false\n      packages:\n' "$name" "$desc" "$sel"
	for p in $pkgs; do printf '        - %s\n' "$p"; done
	# Flatpaks: netinstall only knows packages (and Calamares 3.3 ignores
	# post-install on package entries), so the pick is a marker name that the
	# omaxianpicks job records and strips before the packages module.
	for f in $fps; do printf '        - "omaxian-pick:flatpak:%s"\n' "$f"; done
done
# Optional AppImages: netinstall only knows packages. Each entry is a subgroup
# whose only "package" is the marker omaxian-pick:appimage:<id>, recorded and
# stripped by the omaxianpicks job (before packages); omaxian-firstboot
# downloads the picked ones once online.
if [ -n "$manifest" ]; then
	printf '    - name: "Extra apps (downloaded after install)"\n      description: "AppImages not on the ISO: downloaded into ~/AppImages after installation, once the machine is online"\n      selected: false\n      critical: false\n      hidden: false\n      expanded: true\n      subgroups:\n'
	n=0
	while IFS=$'\t' read -r id glob method source class sha label; do
		[[ -z $id || $id == \#* || ${class:-} != optional ]] && continue
		[[ $id =~ ^[A-Za-z0-9._-]+$ ]] || { echo "gen-netinstall: bad AppImage id '$id'" >&2; exit 1; }
		lname=${label%%: *}; ldesc=${label#*: }; [ -n "$label" ] || { lname=$id; ldesc="$id (AppImage)"; }
		printf '        - name: "%s"\n          description: "%s (AppImage, downloaded after install)"\n          selected: false\n          critical: false\n          hidden: false\n          packages:\n            - "omaxian-pick:appimage:%s"\n' \
			"${lname//\"/}" "${ldesc^}" "$id"
		n=$((n+1))
	done < "$manifest"
	[ $n -gt 0 ] || { echo "gen-netinstall: no optional AppImages in $manifest" >&2; exit 1; }
fi
} > "$out"
