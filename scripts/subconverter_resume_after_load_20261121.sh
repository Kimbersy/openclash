#!/bin/sh
# Resume after the 2026-11-21 verified artifact was successfully docker-loaded
# but its local Docker image ID differed from GitHub runner's image ID.
# No pull, no docker load, no production restart/replacement.
set -eu
umask 077
UPLOAD='/tmp/upload'
ZIP="$UPLOAD/subconverter-0.9.9-amd64-verified.zip"
WORK="$UPLOAD/subconverter-0.9.9-import-stage"
TAR='subconverter-0.9.9-amd64.docker.tar.gz'
CHECK="$TAR.sha256"
META="$TAR.metadata.txt"
IMAGE='asdlokj1qpi23/subconverter:0.9.9'
ZIP_SHA='0ce19f566d2930aba907a508354afe71d6c6e21b706e3ebad816445a75b60ed8'
TEST_SOURCE='https://raw.githubusercontent.com/Kimbersy/openclash/97f87cbaf5317df24ffc563f5615382414dc14cd/scripts/subconverter_sni_timezone_candidate_check.sh'
hold() { echo "HOLD: $1"; echo 'No change to production 25500; retain uploaded files.'; exit 1; }
for cmd in docker sha256sum gzip curl uname; do
    command -v "$cmd" >/dev/null 2>&1 || hold "missing command: $cmd"
done
case "$(uname -m)" in x86_64|amd64) ;; *) hold 'device CPU is not amd64' ;; esac
[ -f "$ZIP" ] || hold 'uploaded ZIP missing'
[ -d "$WORK" ] && [ ! -L "$WORK" ] || hold 'previous import staging directory missing or unsafe'
[ "$(cd "$WORK" && pwd -P)" = "$WORK" ] || hold 'unexpected import staging path'
[ -f "$WORK/$TAR" ] && [ -f "$WORK/$CHECK" ] && [ -f "$WORK/$META" ] || hold 'verified archive or its manifest missing'
read_hash=$(sha256sum "$ZIP") || hold 'cannot compute ZIP checksum'
case "$read_hash" in "$ZIP_SHA "*) echo 'ARTIFACT_ZIP_SHA256=PASS' ;; *) hold 'ZIP checksum mismatch' ;; esac
(cd "$WORK" && sha256sum -c "$CHECK") || hold 'inner Docker archive checksum mismatch'
gzip -t "$WORK/$TAR" || hold 'inner Docker archive gzip integrity failure'
echo 'INNER_IMAGE_SHA256=PASS'

old=$(docker inspect -f '{{.State.Running}}|{{.Image}}' nostalgic_pasteur 2>/dev/null) || hold 'production container not found'
case "$old" in true\|*) ;; *) hold 'production converter is not running' ;; esac
id=$(docker image inspect -f '{{.Id}}' "$IMAGE" 2>/dev/null) || hold 'loaded candidate image not found'
[ -n "$id" ] || hold 'candidate image ID is empty'
[ "$id" != "${old#*|}" ] || hold 'candidate and production image are unexpectedly identical'
arch=$(docker image inspect -f '{{.Architecture}}' "$IMAGE" 2>/dev/null) || hold 'candidate architecture unavailable'
os=$(docker image inspect -f '{{.Os}}' "$IMAGE" 2>/dev/null) || hold 'candidate OS unavailable'
[ -z "$arch" ] || [ "$arch" = 'amd64' ] || hold "wrong candidate architecture: $arch"
[ -z "$os" ] || [ "$os" = 'linux' ] || hold "wrong candidate OS: $os"
echo "CANDIDATE_LOCAL_IMAGE_ID=$id"
if [ -z "$arch" ] || [ -z "$os" ]; then
    echo 'IMAGE_METADATA_PARTIAL=YES (candidate will be verified by real isolated execution)'
else
    echo 'IMAGE_PLATFORM=linux/amd64'
fi

curl -fsSL --connect-timeout 10 --max-time 45 "$TEST_SOURCE" -o "$WORK/test-local.sh" || hold 'cannot download pinned local test script'
sh "$WORK/test-local.sh" --local-image || hold 'SNI / timezone isolated candidate test failed'
echo 'CANDIDATE_ISOLATED_TEST=PASS_NOT_DEPLOYED'

# Exact-path post-pass cleanup; do not touch other files in /tmp/upload or network-watch.
rm -f "$WORK/$TAR" "$WORK/$CHECK" "$WORK/$META" "$WORK/test-local.sh" || hold 'targeted staged cleanup failed'
rmdir "$WORK" || hold 'staging directory not empty; uploaded ZIP preserved'
rm -f "$ZIP" || hold 'artifact ZIP cleanup failed'
echo 'UPLOAD_CLEANUP=PASS_EXACT_FILES_ONLY'
echo 'RESUME_RESULT=PASS_IMAGE_LOADED_TESTED_NOT_DEPLOYED'
