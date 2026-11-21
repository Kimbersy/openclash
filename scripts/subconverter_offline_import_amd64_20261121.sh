#!/bin/sh
# One-time iStoreOS import of a specific, CI-verified GitHub Actions artifact.
# Never stops/replaces production container; only removes this artifact's temporary files after test PASS.
set -eu
umask 077

UPLOAD='/tmp/upload'
ZIP="$UPLOAD/subconverter-0.9.9-amd64-verified.zip"
WORK="$UPLOAD/subconverter-0.9.9-import-stage"
TAR='subconverter-0.9.9-amd64.docker.tar.gz'
CHECK='subconverter-0.9.9-amd64.docker.tar.gz.sha256'
META='subconverter-0.9.9-amd64.docker.tar.gz.metadata.txt'
EXPECTED_ZIP_SHA='0ce19f566d2930aba907a508354afe71d6c6e21b706e3ebad816445a75b60ed8'
EXPECTED_IMAGE_ID='sha256:d95373f215a78e80cfa72e9da1d7a63efa99ff02d7754cfdc909057a36562a28'
IMAGE='asdlokj1qpi23/subconverter:0.9.9'
TEST_SOURCE='https://raw.githubusercontent.com/Kimbersy/openclash/97f87cbaf5317df24ffc563f5615382414dc14cd/scripts/subconverter_sni_timezone_candidate_check.sh'

abort() {
  echo "HOLD: $1"
  echo 'Production nostalgic_pasteur / port 25500 has not been intentionally modified.'
  exit 1
}
[ -f "$ZIP" ] || abort 'uploaded artifact ZIP not found at /tmp/upload'
[ ! -e "$WORK" ] || abort 'import staging directory already exists; do not overwrite'
command -v docker >/dev/null 2>&1 || abort 'docker command missing'
command -v sha256sum >/dev/null 2>&1 || abort 'sha256sum command missing'
command -v gzip >/dev/null 2>&1 || abort 'gzip command missing'
command -v curl >/dev/null 2>&1 || abort 'curl command missing'

arch=$(uname -m)
case "$arch" in x86_64|amd64) ;; *) abort "wrong CPU architecture ($arch), expecting amd64" ;; esac
running=$(docker inspect -f '{{.State.Running}}' nostalgic_pasteur 2>/dev/null) || abort 'production container not found'
[ "$running" = 'true' ] || abort 'production converter not running'

# GitHub Actions immutable artifact ZIP checksum (not the checksum of inner tar.gz).
set -- $(sha256sum "$ZIP")
[ "$1" = "$EXPECTED_ZIP_SHA" ] || abort 'downloaded artifact ZIP digest mismatch'
echo 'ARTIFACT_ZIP_SHA256=PASS'

mkdir "$WORK" || abort 'cannot create private import staging directory'
if command -v unzip >/dev/null 2>&1; then
  unzip -q "$ZIP" -d "$WORK" || abort 'ZIP extraction failed'
elif command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx unzip; then
  busybox unzip -q "$ZIP" -d "$WORK" || abort 'BusyBox ZIP extraction failed'
else
  abort 'unzip is unavailable; original ZIP retained'
fi

[ -f "$WORK/$TAR" ] || abort 'image tar.gz absent from artifact'
[ -f "$WORK/$CHECK" ] || abort 'SHA256 manifest absent from artifact'
[ -f "$WORK/$META" ] || abort 'image metadata absent from artifact'
(cd "$WORK" && sha256sum -c "$CHECK") || abort 'image tar.gz SHA256 mismatch'
gzip -t "$WORK/$TAR" || abort 'gzip integrity failed'
echo 'INNER_IMAGE_SHA256=PASS'

# Load only, no production stop/restart/rebuild.
gzip -dc "$WORK/$TAR" | docker load || abort 'docker load failed'
id=$(docker image inspect -f '{{.Id}}' "$IMAGE" 2>/dev/null) || abort 'expected image tag not loaded'
[ "$id" = "$EXPECTED_IMAGE_ID" ] || abort 'loaded image ID does not match verified CI'
echo 'DOCKER_IMAGE_ID=PASS'

curl -fsSL --connect-timeout 10 --max-time 45 "$TEST_SOURCE" -o "$WORK/test-local.sh" || abort 'pinned local test script download failed'
sh "$WORK/test-local.sh" --local-image || abort 'local candidate test failed'
echo 'LOCAL_CANDIDATE_SNI_AND_TZ=PASS'

# Remove ONLY files created for this one artifact, and only after full verification.
rm -f "$WORK/$TAR" "$WORK/$CHECK" "$WORK/$META" "$WORK/test-local.sh" || abort 'staging files cleanup failed'
rmdir "$WORK" || abort 'staging directory not empty; preserving original uploaded ZIP'
rm -f "$ZIP" || abort 'original uploaded ZIP cleanup failed'
echo 'UPLOAD_CLEANUP=PASS_EXACT_FILES_ONLY'
echo 'IMPORT_RESULT=PASS_VERIFIED_NOT_DEPLOYED'
