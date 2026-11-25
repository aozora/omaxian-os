#!/bin/bash
# test-vm.sh <vm> <base|full> <strata|folio> <hostname> <install-wait-s>: live boot, live checks,
# install, installed boot + checks. Then inspect shots/ and serial logs.
z() { sleep $(( $1 * ${SLOW:-1} )); }
cd /workspace; V=$1 FL=$2 FM=$3 HN=$4 W=$5
bash tools/diag/r19/vm.sh $V $FL uefi cd || exit 1; z 150; bash tools/diag/r19/shot.sh $V live
bash tools/diag/r19/drive-install.sh $V $FM $HN || exit 1
sleep $W; bash tools/diag/r19/shot.sh $V alldone
bash tools/diag/r19/post-install.sh $V $FL uefi
echo TESTVM_END $(date +%T)
