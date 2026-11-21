#!/bin/sh
# Before manual OpenClash subscription refresh after fixed subconverter 0.9.9 cutover.
# Single encrypted? No: protects sensitive source YAML with root-only directory/file permissions.
# No subscription URLs/credentials/content printed; no external updates or production modifications.
set -eu
umask 077
CFG='/etc/openclash/云.yaml'
DIR='/mnt/sata1-4/network-watch/subconverter-099-real-refresh-20261121'
BACKUP="$DIR/云.yaml.before-refresh"
NEW_ID='sha256:ce901e8d55821e510e3093d3da0bb05058ce6af1d55e5fe337c95dc0b8d77b45'
OLD_ID='sha256:1d440885c78a0eee2ea0f7006dbdee92f3c04024fc60cf39cdca9cace98539ca'
hold() { echo "HOLD: $1"; exit 1; }
for cmd in docker curl sha256sum cp chmod mkdir; do
  command -v "$cmd" >/dev/null 2>&1 || hold "required command missing: $cmd"
done
[ -f "$CFG" ] && [ ! -L "$CFG" ] && [ -s "$CFG" ] || hold 'active OpenClash YAML is absent, empty, or symlink'
[ -d /mnt/sata1-4/network-watch ] || hold 'persistent diagnostic directory absent'
[ "$(docker inspect -f '{{.State.Running}}|{{.Image}}|{{.HostConfig.RestartPolicy.Name}}' nostalgic_pasteur 2>/dev/null)" = "true|$NEW_ID|always" ] || hold 'new production container status/image/restart policy not as expected'
[ "$(docker inspect -f '{{.State.Running}}|{{.Image}}' nostalgic_pasteur-pre099-20261121 2>/dev/null)" = "false|$OLD_ID" ] || hold 'old backup container missing or unexpectedly running'
curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 'http://127.0.0.1:25500/version' >/dev/null || hold 'production converter /version is unavailable'
if [ -e "$DIR" ]; then
  [ -d "$DIR" ] && [ ! -L "$DIR" ] || hold 'backup directory exists with unexpected type'
else
  mkdir "$DIR" || hold 'unable to create root-only backup directory'
fi
chmod 700 "$DIR" || hold 'cannot protect backup directory'
[ ! -e "$BACKUP" ] && [ ! -L "$BACKUP" ] || hold 'pre-refresh backup already exists; do not overwrite'
cp "$CFG" "$BACKUP" || hold 'copy of active YAML failed'
chmod 600 "$BACKUP" || hold 'cannot restrict backup file permissions'
a=$(sha256sum "$CFG") || hold 'cannot hash original YAML'
b=$(sha256sum "$BACKUP") || hold 'cannot hash backup YAML'
[ "${a%% *}" = "${b%% *}" ] || hold 'YAML backup checksum differs; do not refresh'
echo 'PRODUCTION_25500=HEALTHY_FIXED_IMAGE'
echo 'OLD_CONTAINER=STOPPED_AND_PRESERVED'
echo 'CURRENT_OPENCLASH_YAML_BACKUP=PASS_CHECKSUM_MATCH_0600'
echo 'BEFORE_REFRESH=PASS_READY_FOR_ONE_MANUAL_SUBSCRIPTION_UPDATE'
echo "BACKUP_LOCATION=$BACKUP"
echo 'NO_SUBSCRIPTION_REFRESH_TRIGGERED_BY_THIS_SCRIPT=YES'
