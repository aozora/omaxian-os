#!/bin/bash
# Generate a THROWAWAY signing key for the local reprepro repo (CI/dev only).
# The real apt.omaxian.org key is generated offline: see docs/signing-key.md.
. "$(dirname "$0")/lib.sh"
need gpg
KD="$TOPDIR/keys"; export GNUPGHOME="$KD/private/gnupg"
mkdir -p "$KD/public" "$GNUPGHOME"; chmod 700 "$KD/private" "$GNUPGHOME"
if ! gpg --list-secret-keys "Omaxian OS TEST" >/dev/null 2>&1; then
	msg "generating throwaway test key (no passphrase, expires 1y)"
	gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
		--quick-gen-key "Omaxian OS TEST archive key (DO NOT TRUST) <test@omaxian.invalid>" ed25519 sign 1y
fi
FPR=$(gpg --list-secret-keys --with-colons "Omaxian OS TEST" | awk -F: '/^fpr/{print $10; exit}')
gpg --export "$FPR" > "$KD/public/omaxian-archive-keyring.pgp"
echo "$FPR" > "$KD/public/fingerprint"
msg "test key $FPR -> keys/public/omaxian-archive-keyring.pgp"
