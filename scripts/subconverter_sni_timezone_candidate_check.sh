#!/bin/sh
# iStoreOS OpenClash: non-disruptive candidate test (no live subscription URLs).
# Dependencies: docker, curl, grep, sh, date (in candidate container).
# Never stop, rename, modify or inspect credentials of the production container.
set -eu
OLD='nostalgic_pasteur'
TEST='subconverter-sni-test-20261121'
IMAGE='asdlokj1qpi23/subconverter:0.9.9'
ENDPOINT='http://127.0.0.1:25501/sub'
mode='pull'
case "${1-}" in
  '') ;;
  --local-image) mode='local' ;;
  *) echo 'Usage: sh subconverter_sni_timezone_candidate_check.sh [--local-image]'; exit 1 ;;
esac
created=0
cleanup() {
    if [ "$created" -eq 1 ]; then
        docker rm -f "$TEST" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
trap 'exit 2' HUP INT TERM

command -v docker >/dev/null 2>&1 || { echo 'HOLD: docker unavailable'; exit 1; }
command -v curl >/dev/null 2>&1 || { echo 'HOLD: curl unavailable'; exit 1; }
command -v grep >/dev/null 2>&1 || { echo 'HOLD: grep unavailable'; exit 1; }

state=$(docker inspect -f '{{.State.Running}}' "$OLD" 2>/dev/null) || {
    echo 'HOLD: original container not found'; exit 1;
}
[ "$state" = 'true' ] || { echo 'HOLD: original container not running'; exit 1; }
# Do not print .Config.Env (may hold secrets).
docker inspect -f 'ORIGINAL=RUNNING NETWORK={{.HostConfig.NetworkMode}} RESTART={{.HostConfig.RestartPolicy.Name}} MOUNTS={{len .Mounts}} IMAGE_ID={{.Image}}' "$OLD"
if docker container inspect "$TEST" >/dev/null 2>&1; then
    echo 'HOLD: temporary test container name already exists; not modifying it'; exit 1
fi

if [ "$mode" = 'local' ]; then
    echo 'CANDIDATE=LOCAL_IMAGE_NO_PULL'
else
    echo 'CANDIDATE=PULLING_NO_PRODUCTION_CHANGE'
    docker pull "$IMAGE" >/dev/null || { echo 'HOLD: candidate pull failed'; exit 1; }
fi
id=$(docker image inspect -f '{{.Id}}' "$IMAGE" 2>/dev/null) || {
    echo 'HOLD: candidate image not present locally'; exit 1;
}
[ -n "$id" ] || { echo 'HOLD: candidate has no image ID'; exit 1; }
echo "CANDIDATE_IMAGE_ID=$id"
docker run -d --name "$TEST" --restart=no \
    -p 127.0.0.1:25501:25500 -e TZ=CST-8 "$id" >/dev/null || {
    echo 'HOLD: candidate temporary container failed to start; 25500 was untouched'; exit 1
}
created=1

# Wait for the local service to respond, without a network test to any airport.
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl --noproxy '*' -fsS --connect-timeout 1 --max-time 3 \
        'http://127.0.0.1:25501/version' >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done
[ "$ready" -eq 1 ] || { echo 'HOLD: candidate /version did not respond'; exit 1; }
echo 'CANDIDATE_VERSION_OK=YES'
offset=$(docker exec "$TEST" date '+%z' 2>/dev/null) || {
    echo 'HOLD: cannot read candidate timezone'; exit 1;
}
echo "CANDIDATE_TZ_OFFSET=$offset"
[ "$offset" = '+0800' ] || { echo 'HOLD: timezone offset is not +0800'; exit 1; }

# Entirely synthetic URI: does not contact a real airport/server.
result=$(curl --noproxy '*' -fsSG --connect-timeout 2 --max-time 15 \
    --data-urlencode 'target=clash' \
    --data-urlencode 'list=true' \
    --data-urlencode 'url=anytls://dummy-password@node.example.invalid:8443?sni=cert.example.invalid#TEST-ANYTLS-SNI' \
    "$ENDPOINT") || { echo 'HOLD: synthetic conversion request failed'; exit 1; }
printf '%s\n' "$result" | grep -q 'TEST-ANYTLS-SNI' || {
    echo 'HOLD: synthetic AnyTLS node absent'; exit 1;
}
printf '%s\n' "$result" | grep -Eq 'sni:[[:space:]]*cert\.example\.invalid' || {
    echo 'HOLD: candidate did not preserve synthetic AnyTLS SNI'; exit 1;
}
echo 'SYNTHETIC_ANYTLS_SNI=PASS'
state=$(docker inspect -f '{{.State.Running}}' "$OLD" 2>/dev/null) || state='missing'
[ "$state" = 'true' ] || { echo 'HOLD: original container state changed'; exit 1; }
echo 'ORIGINAL=STILL_RUNNING'
echo 'CANDIDATE_RESULT=PASS_NOT_DEPLOYED'
