#!/bin/bash
# Build the local apt repo ($LOCALREPO) from $OUTDIR/debs with reprepro.
# Same layout as https://apt.omaxian.org (bucket omaxian-apt), so publishing is
# a plain sync of $LOCALREPO/{dists,pool} (scripts/publish-r2.sh).
# Signing key: keys/private/gnupg (throwaway test key unless GNUPGHOME and
# OMAXIAN_SIGN_KEY point to the real offline key, see docs/signing-key.md).
. "$(dirname "$0")/lib.sh"
need reprepro gpg
[ -f "$TOPDIR/keys/public/fingerprint" ] || "$TOPDIR/scripts/gen-test-key.sh"
export GNUPGHOME="${GNUPGHOME:-$TOPDIR/keys/private/gnupg}"
KEY="${OMAXIAN_SIGN_KEY:-$(cat "$TOPDIR/keys/public/fingerprint")}"
# keys/public/fingerprint names the signing SUBKEY; the trailing "!" makes gpg
# use exactly that (sub)key instead of picking one by itself.
case $KEY in *!) ;; *) KEY="$KEY!" ;; esac
gpg --batch --list-secret-keys "${KEY%!}" >/dev/null 2>&1 || die "no secret key for ${KEY%!} in $GNUPGHOME"
mkdir -p "$LOCALREPO/conf"
cat > "$LOCALREPO/conf/distributions" <<EOD
Origin: apt.omaxian.org
Label: Omaxian OS
Suite: $OMAXIAN_APT_SUITE
Codename: $OMAXIAN_APT_SUITE
Architectures: amd64
Components: main
Description: Omaxian OS packages for Devuan $DEVUAN_SUITE
SignWith: $KEY
EOD
cat > "$LOCALREPO/conf/options" <<EOD
verbose
ask-passphrase
EOD
sed -i '/ask-passphrase/d' "$LOCALREPO/conf/options"
for deb in "$OUTDIR"/debs/*.deb; do
	# full-ISO-only (needs the upstream voxtype .deb from the offline pool)
	case "${deb##*/}" in omaxian-voxtype_*) continue;; esac
	reprepro -b "$LOCALREPO" includedeb "$OMAXIAN_APT_SUITE" "$deb"
done
reprepro -b "$LOCALREPO" export "$OMAXIAN_APT_SUITE"
cp "$TOPDIR/keys/public/omaxian-archive-keyring.pgp" "$LOCALREPO/omaxian-archive-keyring.pgp"
reprepro -b "$LOCALREPO" list "$OMAXIAN_APT_SUITE"
msg "repo ready: $LOCALREPO (signed by $KEY)"
