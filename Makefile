# Omaxian OS image build. Root is needed for rootfs/iso (sudo is used).
#   make keys        # throwaway TEST signing key (real key: docs/signing-key.md)
#   make packages    # build omaxian-* debs into out/debs
#   make repo        # signed local reprepro repo in repo-local/
#   make base        # rootfs + ISO: out/omaxian-base-*.iso
#   make full        # rootfs + ISO: out/omaxian-full-*.iso (needs payload/)
#   make test-base   # QEMU (TCG) boot test, screenshots in shots/
#   make publish-dry # show what publish-r2.sh would upload (no upload)
SHELL := /bin/bash
SUDO  ?= sudo -E
FW    ?= uefi
SECS  ?= 900

.PHONY: all keys fetch packages repo rootfs-base rootfs-full base full iso-base iso-full test-base test-full publish-dry clean distclean
all: base

keys:
	@test -e keys/public/omaxian-archive-keyring.pgp || bash scripts/gen-test-key.sh
fetch:
	bash scripts/fetch-omaxian.sh
	bash scripts/fetch-strata.sh build/pkg/.fetch-strata
	bash scripts/fetch-nerd-fonts.sh build/pkg/.fetch-nerd-fonts
	bash scripts/fetch-voxtype.sh
packages: fetch
	bash scripts/build-packages.sh
repo: keys packages
	bash scripts/make-repo.sh
rootfs-base: repo
	$(SUDO) bash scripts/build-rootfs.sh base
rootfs-full: rootfs-base
	$(SUDO) bash scripts/build-rootfs.sh full
iso-base:
	$(SUDO) bash scripts/build-iso.sh base
iso-full:
	$(SUDO) bash scripts/build-iso.sh full
base: rootfs-base iso-base
full: rootfs-full iso-full
test-base:
	bash scripts/boot-test.sh out/omaxian-base-*-amd64.iso $(FW) $(SECS) base-$(FW)
test-full:
	bash scripts/boot-test.sh out/omaxian-full-*-amd64.iso $(FW) $(SECS) full-$(FW)
publish-dry:
	DRY_RUN=1 bash scripts/publish-r2.sh apt
	DRY_RUN=1 bash scripts/publish-r2.sh iso
clean:
	-$(SUDO) bash scripts/umount-chroot.sh build/rootfs-base
	-$(SUDO) bash scripts/umount-chroot.sh build/rootfs-full
	$(SUDO) rm -rf build/rootfs-* build/iso-* build/pkg
distclean: clean
	$(SUDO) rm -rf build out repo-local
