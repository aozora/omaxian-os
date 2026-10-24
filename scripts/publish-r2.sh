#!/bin/bash
# Publish to Cloudflare R2 (S3 API).  NOT run by the build; run it by hand or in CI.
#   publish-r2.sh apt   -> $LOCALREPO/{dists,pool,omaxian-archive-keyring.pgp} -> s3://omaxian-apt  (https://apt.omaxian.org)
#   publish-r2.sh iso   -> $OUTDIR/*.iso{,.sha256}                              -> s3://omaxian-iso  (https://download.omaxian.org/releases/<version>/)
# Credentials come ONLY from the environment:
#   R2_ACCESS_KEY_ID  R2_SECRET_ACCESS_KEY  R2_ENDPOINT (https://<account-id>.r2.cloudflarestorage.com)
# Options: DRY_RUN=1 (default!) prints what would be uploaded; set DRY_RUN=0 to upload.
#   Without credentials (or without the aws CLI) DRY_RUN=1 prints an offline
#   plan from the local files; DRY_RUN=0 always requires credentials.
. "$(dirname "$0")/lib.sh"
WHAT=${1:?apt|iso}
DRY_RUN=${DRY_RUN:-1}
APT_BUCKET=${APT_BUCKET:-omaxian-apt}; ISO_BUCKET=${ISO_BUCKET:-omaxian-iso}
have_creds() { [ -n "${R2_ACCESS_KEY_ID:-}" ] && [ -n "${R2_SECRET_ACCESS_KEY:-}" ] && [ -n "${R2_ENDPOINT:-}" ] && command -v aws >/dev/null; }
if [ "$DRY_RUN" = 1 ] && ! have_creds; then
	# Offline plan: no credentials, no aws CLI and no network needed.
	OFFLINE=1
	warn "DRY_RUN=1 without R2 credentials/aws: offline plan only (nothing is contacted or uploaded)"
	S3=(r2_plan)
else
	OFFLINE=0
	: "${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID}" "${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}" "${R2_ENDPOINT:?set R2_ENDPOINT}"
	need aws
	export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" AWS_DEFAULT_REGION=auto
	S3=(aws s3 --endpoint-url "$R2_ENDPOINT")
fi
DR=(); [ "$DRY_RUN" = 1 ] && DR=(--dryrun) && warn "DRY_RUN=1: nothing will be uploaded"
# r2_plan sync|cp [--dryrun] <src> <s3://dst> [--cache-control X] [--delete]
r2_plan() {
	local op=$1; shift; [ "${1:-}" = --dryrun ] && shift
	local src=$1 dst=$2; shift 2
	local cc="" del=""
	while [ $# -gt 0 ]; do case $1 in --cache-control) cc=$2; shift 2 ;; --delete) del=" (+delete remote extras)"; shift ;; *) shift ;; esac; done
	if [ ! -e "$src" ]; then warn "(plan) MISSING $src -> $dst (a real publish would fail)"; PLAN_MISSING=$(( ${PLAN_MISSING:-0} + 1 )); return 0; fi
	if [ "$op" = sync ]; then
		local n sz; n=$(find "$src" -type f | wc -l); sz=$(du -sh "$src" | cut -f1)
		printf '(plan) sync %s -> %s  [%s files, %s; cache-control: %s]%s\n' "$src" "$dst" "$n" "$sz" "$cc" "$del"
		find "$src" -type f -printf '         %P\n' | sort | head -20
		[ "$n" -gt 20 ] && echo "         ... $((n-20)) more"
	else
		printf '(plan) upload %s -> %s  [%s; cache-control: %s]\n' "$src" "$dst" "$(du -h "$src" | cut -f1)" "${cc:-default}"
	fi
	return 0
}
case "$WHAT" in
apt)
	[ -f "$LOCALREPO/dists/$OMAXIAN_APT_SUITE/InRelease" ] || die "no signed repo in $LOCALREPO"
	FPR=$(gpg --show-keys --with-colons "$LOCALREPO/omaxian-archive-keyring.pgp" | awk -F: '/^fpr/{print $10; exit}')
	if gpg --show-keys "$LOCALREPO/omaxian-archive-keyring.pgp" | grep -q 'DO NOT TRUST'; then
		if [ "$DRY_RUN" = 1 ]; then warn "repo is signed with the THROWAWAY test key ($FPR); a real publish would refuse (see docs/signing-key.md)"
		else [ "${ALLOW_TEST_KEY:-0}" = 1 ] || die "repo is signed with the THROWAWAY test key ($FPR); refusing (see docs/signing-key.md)"; fi
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
[ "${PLAN_MISSING:-0}" -gt 0 ] && warn "$PLAN_MISSING file(s) missing for a real publish"
msg "publish $WHAT finished (DRY_RUN=$DRY_RUN${OFFLINE:+, offline=$OFFLINE})"
