#!/bin/bash
# config/optional-groups.list -> Calamares netinstall.conf (local groups)
#   gen-netinstall.sh <optional-groups.list> <netinstall.conf> [more.list ...]
# (the full ISO adds config/optional-groups-full.list)
set -eu
in=$1 out=$2; shift 2
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
grep -hvE '^\s*(#|$)' "$in" "$@" | while IFS='|' read -r id name desc sel pkgs; do
	printf '    - name: "%s"\n      description: "%s"\n      selected: %s\n      critical: false\n      hidden: false\n      packages:\n' "$name" "$desc" "$sel"
	for p in $pkgs; do printf '        - %s\n' "$p"; done
done
} > "$out"
