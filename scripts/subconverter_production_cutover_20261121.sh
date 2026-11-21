#!/bin/sh
# One-time iStoreOS subconverter 0.9.9 production cutover.
# Fixed old/new image IDs, exact old runtime contract, guarded rollback.
# Does not modify OpenClash, other Docker containers, firewall, DNS or subscription data.
set -eu

OLD='nostalgic_pasteur'
BACKUP='nostalgic_pasteur-pre099-20261121'
OLD_ID='sha256:1d440885c78a0eee2ea0f7006dbdee92f3c04024fc60cf39cdca9cace98539ca'
NEW_ID='sha256:ce901e8d55821e510e3093d3da0bb05058ce6af1d55e5fe337c95dc0b8d77b45'
NEW_TAG='asdlokj1qpi23/subconverter:0.9.9'
BASE='http://127.0.0.1:25500'
started=0
committed=0

die() { echo "HOLD: $1"; exit 1; }
status() { docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null; }
image() { docker inspect -f '{{.Image}}' "$1" 2>/dev/null; }
old_field() { docker inspect -f "$1" "$OLD" 2>/dev/null; }

rollback() {
  code=$?
  trap - EXIT HUP INT TERM
  [ "$committed" -eq 0 ] || exit "$code"
  if [ "$started" -eq 0 ]; then
    echo 'CUTOVER_RESULT=HOLD_BEFORE_CHANGE'
    exit 1
  fi
  set +e
  echo 'CUTOVER_RESULT=HOLD_ROLLBACK_ATTEMPTED'
  if docker container inspect "$BACKUP" >/dev/null 2>&1; then
    if docker container inspect "$OLD" >/dev/null 2>&1; then
      new_current=$(image "$OLD")
      if [ "$new_current" = "$NEW_ID" ]; then
        docker rm -f "$OLD" >/dev/null 2>&1 || echo 'ROLLBACK_WARNING=NEW_CONTAINER_COULD_NOT_BE_REMOVED'
      else
        echo 'ROLLBACK_HOLD=UNEXPECTED_CONTAINER_AT_ORIGINAL_NAME'
      fi
    fi
    if ! docker container inspect "$OLD" >/dev/null 2>&1; then
      docker rename "$BACKUP" "$OLD" || echo 'ROLLBACK_WARNING=ORIGINAL_RENAME_FAILED'
    fi
  fi
  old_current=$(image "$OLD")
  if [ "$old_current" = "$OLD_ID" ]; then
    docker update --restart=always "$OLD" >/dev/null || echo 'ROLLBACK_WARNING=RESTART_POLICY_NOT_RESTORED'
    if [ "$(status "$OLD")" != true ]; then
      docker start "$OLD" >/dev/null || echo 'ROLLBACK_WARNING=OLD_START_FAILED'
    fi
    if [ "$(status "$OLD")" = true ] && curl --noproxy '*' -fsS --max-time 5 "$BASE/version" >/dev/null 2>&1; then
      echo 'ROLLBACK_RESULT=OLD_VERSION_ENDPOINT_RESTORED'
    else
      echo 'ROLLBACK_RESULT=HOLD_MANUAL_RECOVERY_NEEDED'
    fi
  else
    echo 'ROLLBACK_RESULT=HOLD_ORIGINAL_IMAGE_ID_MISMATCH'
  fi
  exit 1
}
trap rollback EXIT
trap 'exit 1' HUP INT TERM

for tool in docker curl grep sed; do
  command -v "$tool" >/dev/null 2>&1 || die "missing dependency $tool"
done
[ "$(status "$OLD")" = true ] || die 'old container not running'
[ "$(image "$OLD")" = "$OLD_ID" ] || die 'old container image drifted'
[ "$(docker image inspect -f '{{.Id}}' "$NEW_TAG" 2>/dev/null)" = "$NEW_ID" ] || die 'verified candidate image missing or changed'
docker image inspect "$OLD_ID" >/dev/null 2>&1 || die 'old rollback image missing'
docker network inspect default >/dev/null 2>&1 || die 'original Docker network not available'
if docker container inspect "$BACKUP" >/dev/null 2>&1; then die 'backup name already exists; avoid repeated cutover'; fi

[ "$(old_field '{{.HostConfig.NetworkMode}}')" = default ] || die 'network drift'
[ "$(old_field '{{.HostConfig.RestartPolicy.Name}}')" = always ] || die 'restart policy drift'
[ "$(old_field '{{json .HostConfig.PortBindings}}')" = '{"25500/tcp":[{"HostIp":"","HostPort":"25500"}]}' ] || die 'port binding drift'
[ "$(old_field '{{len .Mounts}}')" = 0 ] || die 'mounts added'
[ "$(old_field '{{len .HostConfig.Binds}}')" = 0 ] || die 'binds added'
[ "$(old_field '{{len .HostConfig.Devices}}')" = 0 ] || die 'devices added'
[ "$(old_field '{{.HostConfig.Privileged}}')" = false ] || die 'privileged mode drift'
[ "$(old_field '{{.HostConfig.ReadonlyRootfs}}')" = false ] || die 'filesystem mode drift'
[ "$(old_field '{{json .Config.Entrypoint}}')" = null ] || die 'entrypoint drift'
[ "$(old_field '{{json .Config.Cmd}}')" = '["/bin/sh","-c","subconverter"]' ] || die 'command drift'
[ "$(old_field '{{.Config.WorkingDir}}')" = /base ] || die 'working directory drift'
[ "$(old_field '{{.Config.User}}')" = '' ] || die 'container user drift'
[ "$(old_field '{{len .Config.Env}}')" = 2 ] || die 'unexpected environment variable count'
names=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$OLD" | sed 's/=.*//') || die 'cannot read environment names'
printf '%s\n' "$names" | grep -qx PATH || die 'PATH variable absent'
printf '%s\n' "$names" | grep -qx TZ || die 'TZ variable absent'
curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 "$BASE/version" >/dev/null || die 'old production version endpoint not healthy'
echo 'PREFLIGHT=PASS_OLD_HEALTHY_CANDIDATE_PINNED'
echo 'SHORT_SERVICE_INTERRUPTION=BEGIN'
started=1

docker stop -t 10 "$OLD" >/dev/null || die 'failed stopping old container'
docker rename "$OLD" "$BACKUP" || die 'failed preserving old container under backup name'
docker update --restart=no "$BACKUP" >/dev/null || die 'failed disabling automatic restart on stopped backup'
docker run -d --name "$OLD" --restart=no --network default \
  -p 25500:25500 -w /base -e TZ=CST-8 \
  "$NEW_ID" /bin/sh -c subconverter >/dev/null || die 'new container failed to start'

ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if [ "$(status "$OLD")" = true ] && curl --noproxy '*' -fsS --connect-timeout 1 --max-time 3 "$BASE/version" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
[ "$ready" -eq 1 ] || die 'new production version endpoint unhealthy'
[ "$(image "$OLD")" = "$NEW_ID" ] || die 'new production image mismatch'
tz=$(docker exec "$OLD" date '+%z') || die 'new container timezone check failed'
[ "$tz" = '+0800' ] || die "new timezone wrong ($tz)"
echo 'PRODUCTION_TZ=+0800'

result=$(curl --noproxy '*' -fsSG --connect-timeout 2 --max-time 15 \
  --data-urlencode 'target=clash' \
  --data-urlencode 'list=true' \
  --data-urlencode 'url=anytls://dummy-password@node.example.invalid:8443?sni=cert.example.invalid#TEST-ANYTLS-SNI' \
  "$BASE/sub") || die 'new production synthetic conversion unavailable'
printf '%s\n' "$result" | grep -q 'TEST-ANYTLS-SNI' || die 'synthetic AnyTLS node missing'
printf '%s\n' "$result" | grep -Eq 'sni:[[:space:]]*cert\.example\.invalid' || die 'AnyTLS SNI missing on live 25500'
echo 'PRODUCTION_SYNTHETIC_ANYTLS_SNI=PASS'

docker update --restart=always "$OLD" >/dev/null || die 'new restart policy update failed'
[ "$(old_field '{{.HostConfig.RestartPolicy.Name}}')" = always ] || die 'new restart policy verification failed'
[ "$(status "$OLD")" = true ] || die 'new container stopped before commit'
[ "$(status "$BACKUP")" = false ] || die 'backup unexpectedly running'
[ "$(image "$BACKUP")" = "$OLD_ID" ] || die 'backup old image identity mismatch'
committed=1
echo "BACKUP_CONTAINER=$BACKUP"
echo "NEW_IMAGE_ID=$NEW_ID"
echo 'CUTOVER_RESULT=PASS_NEW_25500_RUNNING_OLD_BACKUP_STOPPED'
echo 'REAL_SUBSCRIPTION_A01_VLESS=NOT_YET_VERIFIED'
echo 'KEEP_BACKUP_FOR_ROLLBACK=YES'
