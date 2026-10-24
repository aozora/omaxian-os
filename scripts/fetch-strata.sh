#!/bin/bash
# Download the signed Strata release and verify it exactly like upstream
# install.sh does: Ed25519 signature over "strata-update-manifest-v1\0"+manifest
# (openssl pkeyutl, trusted raw keys from config/build.conf), then the archive
# size + SHA-256 listed in the signed manifest. Extracts into $1.
#   fetch-strata.sh <outdir>      (uses STRATA_VERSION)
set -euo pipefail
. "$(dirname "$0")/../config/build.conf"
OUT=${1:?outdir}
VER=$STRATA_VERSION
TARGET=x86_64-unknown-linux-gnu
ARCHIVE="strata-$VER-$TARGET.tar.gz"
BASE="https://github.com/$STRATA_REPO/releases/download/v$VER"
MAX_ARCHIVE_BYTES=$((512*1024*1024))
DL="$BUILDDIR/dl/strata-$VER"; mkdir -p "$DL" "$OUT"
hex_to_bytes() { printf "$(sed 's/../\\x&/g' <<<"$1")"; }
fetch() { # name max-bytes
	[ -s "$DL/$1" ] && return 0
	curl --fail --location --silent --show-error --max-filesize "$2" -o "$DL/$1.part" "$BASE/$1"
	mv "$DL/$1.part" "$DL/$1"
}
fetch strata-update-manifest.json 1048576
fetch strata-update-manifest.signatures.json 1048576
fetch "$ARCHIVE" $MAX_ARCHIVE_BYTES
M="$DL/strata-update-manifest.json"; S="$DL/strata-update-manifest.signatures.json"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# 1. signature
mapfile -t entries < <(grep -oE '\{"key_id":"[0-9a-f]{64}","signature":"[0-9a-f]{128}"\}' "$S")
{ printf 'strata-update-manifest-v1\0'; cat "$M"; } > "$TMP/msg"
ok=0
for key in $STRATA_RELEASE_KEYS; do
	kid=$(hex_to_bytes "$key" | sha256sum | sed 's/ .*//')
	hex_to_bytes "302a300506032b6570032100$key" > "$TMP/key.der"
	for e in "${entries[@]}"; do
		[[ $e == "{\"key_id\":\"$kid\","* ]] || continue
		sig=${e#*\"signature\":\"}; hex_to_bytes "${sig%\"\}}" > "$TMP/sig"
		if openssl pkeyutl -verify -rawin -pubin -keyform DER -inkey "$TMP/key.der" -sigfile "$TMP/sig" -in "$TMP/msg" >/dev/null; then ok=1; break 2; fi
	done
done
[ $ok = 1 ] || { echo "!! no trusted key signed the Strata manifest" >&2; exit 1; }
echo ":: strata manifest signature OK (key_id $kid)"

# 2. manifest describes this release + archive
content=$(<"$M")
pat="^\\{\"artifacts\":\\[.*\\],\"repository\":\"$STRATA_REPO\",\"schema\":1,\"source_commit\":\"[0-9a-f]{40}\",\"tag\":\"v${VER//./\\.}\"\\}$"
[[ $content =~ $pat ]] || { echo "!! manifest is not for $STRATA_REPO v$VER" >&2; exit 1; }
pat="\\{\"name\":\"${ARCHIVE//./\\.}\",\"sha256\":\"([0-9a-f]{64})\",\"size\":([1-9][0-9]*),\"target\":\"$TARGET\"\\}"
[[ $content =~ $pat ]] || { echo "!! manifest does not list $ARCHIVE" >&2; exit 1; }
want_sha=${BASH_REMATCH[1]}; want_size=${BASH_REMATCH[2]}
size=$(wc -c < "$DL/$ARCHIVE"); sha=$(sha256sum "$DL/$ARCHIVE" | sed 's/ .*//')
[ "$size" = "$want_size" ] && [ "$sha" = "$want_sha" ] || { echo "!! $ARCHIVE size/sha256 mismatch ($size/$sha vs $want_size/$want_sha)" >&2; exit 1; }
echo ":: $ARCHIVE sha256 OK ($sha)"

# 3. extract
rm -rf "$OUT"/*; tar -xzf "$DL/$ARCHIVE" -C "$OUT" --strip-components=1
ls "$OUT"
echo "$VER" > "$OUT/.version"; echo "$sha" > "$OUT/.sha256"
