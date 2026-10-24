#!/bin/bash
# Publish to Cloudflare R2 (S3 API).  NOT run by the build; run it by hand or in CI.
#   publish-r2.sh apt   -> $LOCALREPO/{dists,pool,omaxian-archive-keyring.pgp} -> s3://omaxian-apt  (https://apt.omaxian.org)
#   publish-r2.sh iso   -> $OUTDIR/*.iso{,.sha256}                              -> s3://omaxian-iso  (https://download.omaxian.org/releases/<version>/)
# Credentials come ONLY from the environment:
#   R2_ACCESS_KEY_ID  R2_SECRET_ACCESS_KEY  R2_ENDPOINT (https://<account-id>.r2.cloudflarestorage.com)
# Options: DRY_RUN=1 (default!) prints what would be uploaded; set DRY_RUN=0 to upload.
. "$(dirname "$0")/lib.sh"
WHAT=${1:?apt|iso}
DRY_RUN=${DRY_RUN:-1}
APT_BUCKET=${APT_BUCKET:-omaxian-apt}; ISO_BUCKET=${ISO_BUCKET:-omaxian-iso}
: "${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID}" "${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}" "${R2_ENDPOINT:?set R2_ENDPOINT}"
need aws
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" AWS_DEFAULT_REGION=auto
S3=(aws s3 --endpoint-url "$R2_ENDPOINT")
DR=(); [ "$DRY_RUN" = 1 ] && DR=(--dryrun) && warn "DRY_RUN=1: nothing will be uploaded"
case "$WHAT" in
apt)
	[ -f "$LOCALREPO/dists/$OMAXIAN_APT_SUITE/InRelease" ] || die "no signed repo in $LOCALREPO"
	FPR=$(gpg --show-keys --with-colons "$LOCALREPO/omaxian-archive-keyring.pgp" | awk -F: '/^fpr/{print $10; exit}')
	if gpg --show-keys "$LOCALREPO/omaxian-archive-keyring.pgp" | grep -q 'DO NOT TRUST'; then
		[ "${ALLOW_TEST_KEY:-0}" = 1 ] || die "repo is signed with the THROWAWAY test key ($FPR); refusing (see docs/signing-key.md)"
	fi
	# pool first (immutable, long cache), then indices (short cache) so clients never see dangling indices
	"${S3[@]}" sync "${DR[@]}" "$LOCALREPO/pool"  "s3://$APT_BUCKET/pool"  --cache-control "public, max-age=31536000, immutable"
	"${S3[@]}" sync "${DR[@]}" "$LOCALREPO/dists" "s3://$APT_BUCKET/dists" --cache-control "public, max-age=300" --delete
	"${S3[@]}" cp   "${DR[@]}" "$LOCALREPO/omaxian-archive-keyring.pgp" "s3://$APT_BUCKET/omaxian-archive-keyring.pgp" --cache-control "public, max-age=3600"
	;;
iso)
	V=$(echo "$OMAXIAN_VERSION" | tr '~' '-')
	for f in "$OUTDIR"/omaxian-*-"$V"-*.iso; do
		[ -e "$f" ] || die "no ISOs for $V in $OUTDIR"
		"${S3[@]}" cp "${DR[@]}" "$f"        "s3://$ISO_BUCKET/releases/$V/$(basename "$f")"
		"${S3[@]}" cp "${DR[@]}" "$f.sha256" "s3://$ISO_BUCKET/releases/$V/$(basename "$f").sha256"
	done
	;;
*) die "usage: $0 apt|iso" ;;
esac
msg "publish $WHAT finished (DRY_RUN=$DRY_RUN)"
