#!/bin/bash
# Re-sign $LOCALREPO with the owner's Omaxian archive key. Does not upload.
# See docs/signing-key.md.
#
# Required environment:
#   OMAXIAN_SIGNING_KEY
#       ASCII-armored GPG secret of the signing subkey
#       (gpg --armor --export-secret-subkeys <fingerprint>!)
# Optional:
#   OMAXIAN_SIGNING_PASSPHRASE
#       Only if that key has a passphrase. The published subkey has none.
#   OMAXIAN_SIGN_KEY
#       Expected signing-key fingerprint, without a trailing "!".
#       Defaults to the published subkey 5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75.
#   LOCALREPO
#       Round 19 repo is $TOPDIR/build/r19/repo.
#
# The secret is imported into keys/private/gnupg (gitignored) and never printed.
# This replaces the throwaway signature on the apt indices. It does not rebuild
# omaxian-base or the ISOs, which still carry the keyring they were built with.
. "$(dirname "$0")/lib.sh"
need gpg reprepro gpgv
[ -n "${OMAXIAN_SIGNING_KEY:-}" ] || die "set OMAXIAN_SIGNING_KEY to the armored signing subkey"
[ -f "$LOCALREPO/conf/distributions" ] || die "no repo at $LOCALREPO (set LOCALREPO)"

export GNUPGHOME="${GNUPGHOME:-$TOPDIR/keys/private/gnupg}"
mkdir -p "$GNUPGHOME" "$TOPDIR/keys/public"
chmod 700 "$GNUPGHOME"

kf=$(mktemp)
chmod 600 "$kf"
trap 'rm -f "$kf"' EXIT
printf '%s\n' "$OMAXIAN_SIGNING_KEY" > "$kf"
if [ -n "${OMAXIAN_SIGNING_PASSPHRASE:-}" ]; then
	gpg --batch --pinentry-mode loopback --passphrase-fd 3 --import "$kf" 3<<<"$OMAXIAN_SIGNING_PASSPHRASE"
else
	gpg --batch --import "$kf"
fi
rm -f "$kf"

# Prefer a signing subkey. The primary is certify-only.
KEY=$(gpg --batch --with-colons --list-secret-keys | awk -F: '
	$1 == "sec" || $1 == "ssb" { cap = $12; kind = $1; next }
	$1 == "fpr" && cap ~ /s/ {
		if (kind == "ssb" && sub == "") sub = $10
		if (kind == "sec" && pri == "") pri = $10
	}
	END { if (sub != "") print sub; else print pri }
')
[ -n "$KEY" ] || die "imported key has no signing-capable secret key"
EXPECT=${OMAXIAN_SIGN_KEY:-5CD4C2DB72E18C42DB59FD87F899ACD0AF4C4E75}
EXPECT=${EXPECT%!}
[ "$KEY" = "$EXPECT" ] || die "imported signing key $KEY is not $EXPECT"
gpg --batch --list-keys "$KEY" | grep -q 'DO NOT TRUST' && die "refusing the throwaway test key"

printf '%s\n' "$KEY" > "$TOPDIR/keys/public/fingerprint"
gpg --batch --export "$KEY" > "$TOPDIR/keys/public/omaxian-archive-keyring.pgp"

sign="$KEY!"
sed -i "s/^SignWith:.*/SignWith: $sign/" "$LOCALREPO/conf/distributions"
grep -qx "SignWith: $sign" "$LOCALREPO/conf/distributions" || die "could not set SignWith in $LOCALREPO"
reprepro -b "$LOCALREPO" export "$OMAXIAN_APT_SUITE"
cp "$TOPDIR/keys/public/omaxian-archive-keyring.pgp" "$LOCALREPO/omaxian-archive-keyring.pgp"
gpgv --keyring "$LOCALREPO/omaxian-archive-keyring.pgp" \
	"$LOCALREPO/dists/$OMAXIAN_APT_SUITE/InRelease"
msg "repo re-signed by $KEY. Nothing uploaded."
warn "omaxian-base and both ISOs still embed the keyring from this build. Rebuild them with the real public keyring before publishing, or a fresh 0.3 install will not trust apt.omaxian.org."
