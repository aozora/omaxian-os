# Omaxian OS archive signing key

The repo in `repo-local/` is signed with a **throwaway TEST key** made by
`scripts/gen-test-key.sh`. Its UID says "DO NOT TRUST" and `publish-r2.sh` won't
upload anything signed with it unless you set `ALLOW_TEST_KEY=1`.

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
4. Set `Enabled: yes` in `omaxian.sources` once the real repo is live.

Never commit anything under `keys/` (it's in .gitignore).
