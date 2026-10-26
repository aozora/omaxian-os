# Omaxian OS archive signing key

Since 2026-10-25 `repo-local/` (and so https://apt.omaxian.org) is signed with the
**real** key:

| | fingerprint | expires |
|---|---|---|
| primary (certify only, kept offline) | `1D8D E9AD 3AFA 6079 0333  639E F45C 7450 C45D 49A0` | 2031-10-24 |
| signing subkey (reprepro / CI) | `5CD4 C2DB 72E1 8C42 DB59  FD87 F899 ACD0 AF4C 4E75` | 2028-10-24 |

- `keys/public/omaxian-archive-keyring.pgp`: the public keyring (primary + subkey).
  build-packages copies it into omaxian-base as
  `/usr/share/keyrings/omaxian-archive-keyring.pgp` (since omaxian-base 0.1.6), and
  make-repo.sh puts it at the repo root.
- `keys/public/fingerprint`: the signing **subkey**. make-repo.sh writes
  `SignWith: <subkey>!` (the `!` pins exactly that subkey) and checks that
  `$GNUPGHOME` (default `keys/private/gnupg`) holds its secret part. The subkey
  has no passphrase, so signing is non-interactive.
- Override with `GNUPGHOME=... OMAXIAN_SIGN_KEY=<fpr>` (e.g. in CI).
- The old throwaway TEST key (`CD76E531...62F519588AAF47F4`, UID "DO NOT TRUST") is
  removed from `keys/private/gnupg`. `scripts/gen-test-key.sh` only runs when
  `keys/public/fingerprint` is missing. `publish-r2.sh` still refuses to upload
  a repo signed with a test key unless `ALLOW_TEST_KEY=1`.
- Systems with omaxian-base <= 0.1.5 (all ISOs built before 2026-10-25 20:00 CET)
  trust only the test key. They need omaxian-base 0.1.6 or a rebuilt ISO before
  they can verify the real repo. See "Rotation" below.

## Rotation (new signing subkey)
On the offline machine: `gpg --quick-add-key <primary> ed25519 sign 2y`, export
the public keyring again and the new secret subkey. Replace both files in
`keys/public/` and the subkey in `keys/private/gnupg`. Bump omaxian-base, rebuild it,
then run `make-repo.sh` (re-signs) and `publish-r2.sh apt`. Because the primary
key is unchanged, clients only need the refreshed keyring before the old subkey
expires.

## Generating the real key (offline machine)

```sh
export GNUPGHOME=$(mktemp -d); chmod 700 $GNUPGHOME
# 1. primary key: certify only, long-lived, kept offline
gpg --quick-gen-key "Omaxian OS Archive Signing Key <archive@omaxian.org>" ed25519 cert 5y
FPR=$(gpg --with-colons --list-keys | awk -F: '/^fpr/{print $10; exit}')
# 2. signing subkey used by CI / reprepro, rotate every 1-2 years
gpg --quick-add-key "$FPR" ed25519 sign 2y
# 3. revocation certificate + backups (store offline, e.g. 2 USB sticks + paper)
gpg --output omaxian-revoke.asc --gen-revoke "$FPR"
gpg --armor --export-secret-keys "$FPR" > omaxian-primary-SECRET.asc
# 4. export ONLY the signing subkey for CI (secret OMAXIAN_SIGNING_KEY)
gpg --armor --export-secret-subkeys "$FPR!" >/dev/null   # (sanity)
SUB=$(gpg --with-colons --list-keys "$FPR" | awk -F: '/^sub/{getline; print $10; exit}')
gpg --armor --export-secret-subkeys "${SUB}!" > omaxian-signing-subkey-SECRET.asc
# 5. public keyring that gets shipped in omaxian-base and to https://apt.omaxian.org/
gpg --export "$FPR" > omaxian-archive-keyring.pgp
```

Then:
1. Put `omaxian-archive-keyring.pgp` + `fingerprint` (the signing subkey's) into `keys/public/`
   and the GNUPGHOME holding the subkey at `keys/private/gnupg` (CI imports it there);
   build-packages copies the public keyring into omaxian-base. Bump omaxian-base.
2. Store `omaxian-signing-subkey-SECRET.asc` as the GitHub secret `OMAXIAN_SIGNING_KEY`.
3. Publish the fingerprint on omaxian.org (HTTPS) so users can check it.
4. Set `Enabled: yes` in `omaxian.sources` once the real repo is live (done in omaxian-base 0.1.7).

Never commit anything under `keys/` (it's in .gitignore).
