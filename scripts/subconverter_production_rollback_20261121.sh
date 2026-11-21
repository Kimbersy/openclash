#!/bin/sh
# Manual emergency rollback AFTER a successful subconverter 0.9.9 cutover.
# Preserve the new container under a stopped name; restore exact original container.
set -eu
LIVE='nostalgic_pasteur'
BACKUP='nostalgic_pasteur-pre099-20261121'
FAILED_NEW='nostalgic_pasteur-099-held-20261121'
OLD_ID='sha256:1d440885c78a0eee2ea0f7006dbdee92f3c04024fc60cf39cdca9cace98539ca'
NEW_ID='sha256:ce901e8d55821e510e3093d3da0bb05058ce6af1d55e5fe337c95dc0b8d77b45'
hold() { echo "HOLD: $1"; exit 1; }
img() { docker inspect -f '{{.Image}}' "$1" 2>/dev/null; }
state() { docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null; }
[ "$(img "$LIVE")" = "$NEW_ID" ] || hold 'current container is not the known 0.9.9 candidate'
[ "$(img "$BACKUP")" = "$OLD_ID" ] || hold 'original backup container missing or changed'
[ "$(state "$BACKUP")" = false ] || hold 'old backup is already running'
if docker container inspect "$FAILED_NEW" >/dev/null 2>&1; then hold 'held-new container name already exists'; fi
echo 'ROLLBACK_PREFLIGHT=PASS'

# Keep the old container unchanged; park new so diagnostic state can be inspected.
docker update --restart=no "$LIVE" >/dev/null || hold 'cannot change new restart policy'
if [ "$(state "$LIVE")" = true ]; then
  docker stop -t 10 "$LIVE" >/dev/null || hold 'cannot stop new container'
fi
docker rename "$LIVE" "$FAILED_NEW" || {
  docker update --restart=always "$LIVE" >/dev/null 2>&1 || true
  docker start "$LIVE" >/dev/null 2>&1 || true
  hold 'new container rename failed; attempted restart'
}
if ! docker rename "$BACKUP" "$LIVE"; then
  docker rename "$FAILED_NEW" "$LIVE" >/dev/null 2>&1 || true
  docker update --restart=always "$LIVE" >/dev/null 2>&1 || true
  docker start "$LIVE" >/dev/null 2>&1 || true
  hold 'original container rename failed; attempted to restore new'
fi
docker update --restart=always "$LIVE" >/dev/null || hold 'old container restart policy not restored'
docker start "$LIVE" >/dev/null || hold 'old container restart failed'
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if [ "$(state "$LIVE")" = true ] && curl --noproxy '*' -fsS --connect-timeout 1 --max-time 3 http://127.0.0.1:25500/version >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
[ "$ready" = 1 ] || hold 'old version endpoint not ready; investigate before any other change'
[ "$(img "$LIVE")" = "$OLD_ID" ] || hold 'restored container image not old image'
echo "NEW_HELD_CONTAINER=$FAILED_NEW"
echo 'ROLLBACK_RESULT=PASS_ORIGINAL_RESTORED_AT_25500'
