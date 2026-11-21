#!/bin/sh
# Candidate helper ONLY. To be called from the existing clash-home watcher lock.
# check -> preexisting refresh/validate -> ack on success or fail on error.
# It never invokes a conversion, replaces a cache, edits cron, or exposes source values.
set -eu
umask 077
MODE=${1:-}
[ "$#" -ge 2 ] || { echo 'HOLD=MODE_AND_INPUT_FILES_REQUIRED'; exit 2; }
shift
case "$MODE" in check|ack|fail) ;; *) echo 'HOLD=INVALID_MODE'; exit 2;; esac
ROOT=${CLASH_HOME_ROOT:-/mnt/sata1-4/clash-home}
STATE_DIR=${CLASH_HOME_CHANGE_STATE:-$ROOT/cache/.input-change-state}
CACHE=${CLASH_HOME_CACHE:-$ROOT/cache/merged.yaml}
MIN_AGE=${CLASH_HOME_MIN_AGE:-180}
BACKOFF=${CLASH_HOME_FAILURE_BACKOFF:-3600}
case "$MIN_AGE:$BACKOFF" in *[!0-9:]*|:*) echo 'HOLD=INVALID_TIMER_CONFIG'; exit 2;; esac
for cmd in docker stat date sha256sum mkdir mv rm ruby; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "HOLD=MISSING_COMMAND_$cmd"; exit 2; }
done
[ -d "$ROOT" ] && [ ! -L "$ROOT" ] || { echo 'HOLD=ROOT_MISSING'; exit 2; }
if [ -e "$STATE_DIR" ] && [ ! -d "$STATE_DIR" ]; then echo 'HOLD=STATE_NOT_DIRECTORY'; exit 2; fi
if [ -L "$STATE_DIR" ]; then echo 'HOLD=STATE_IS_SYMLINK'; exit 2; fi
mkdir -p "$STATE_DIR" || { echo 'HOLD=STATE_UNWRITABLE'; exit 2; }
chmod 700 "$STATE_DIR" || { echo 'HOLD=STATE_PERMISSIONS'; exit 2; }
TMP="$STATE_DIR/.fingerprint-$$"
trap 'rm -f "$TMP" "$STATE_DIR/.pending-$$" "$STATE_DIR/.done-$$" "$STATE_DIR/.failed-$$"' EXIT
trap 'exit 2' HUP INT TERM
now=$(date +%s)
image=$(docker inspect -f '{{.Image}}' nostalgic_pasteur 2>/dev/null) || { echo 'HOLD=CONVERTER_NOT_FOUND'; exit 2; }
case "$image" in sha256:*) ;; *) echo 'HOLD=CONVERTER_BAD_IMAGE_ID'; exit 2;; esac
printf 'CONVERTER_IMAGE=%s\n' "$image" > "$TMP"
count=0
for file in "$@"; do
  [ -f "$file" ] && [ ! -L "$file" ] && [ -s "$file" ] || { echo 'HOLD=INVALID_INPUT_FILE'; exit 2; }
  size=$(stat -c %s "$file" 2>/dev/null) || { echo 'HOLD=INPUT_STAT_FAILED'; exit 2; }
  [ "$size" -le 16777216 ] || { echo 'HOLD=INPUT_TOO_LARGE'; exit 2; }
  ts=$(stat -c %Y "$file" 2>/dev/null) || { echo 'HOLD=INPUT_MTIME_FAILED'; exit 2; }
  if [ "$now" -lt "$ts" ] || [ $((now - ts)) -lt "$MIN_AGE" ]; then
    echo 'EVENT=DEFER_INPUT_STILL_SETTLING'
    exit 0
  fi
  sum=$(sha256sum "$file") || { echo 'HOLD=INPUT_HASH_FAILED'; exit 2; }
  sum=${sum%% *}
  printf 'INPUT=%s %s\n' "$file" "$sum" >> "$TMP"
  count=$((count+1))
done
[ "$count" -gt 0 ] || { echo 'HOLD=NO_INPUT_FILE'; exit 2; }
sum=$(sha256sum "$TMP") || { echo 'HOLD=FINGERPRINT_FAILED'; exit 2; }
new=${sum%% *}
DONE="$STATE_DIR/done.sha256"
PENDING="$STATE_DIR/pending.sha256"
FAILED="$STATE_DIR/failed.state"
if [ "$MODE" = check ]; then
  if [ -f "$DONE" ] && [ "$(cat "$DONE")" = "$new" ]; then
    echo 'EVENT=UNCHANGED'
    exit 0
  fi
  if [ -f "$FAILED" ]; then
    IFS=' ' read -r bad at < "$FAILED" || true
    case "$at" in ''|*[!0-9]*) at=0;; esac
    if [ "$bad" = "$new" ] && [ "$now" -ge "$at" ] && [ $((now - at)) -lt "$BACKOFF" ]; then
      echo 'EVENT=BACKOFF_AFTER_FAILED_REFRESH'
      exit 0
    fi
  fi
  printf '%s\n' "$new" > "$STATE_DIR/.pending-$$"
  mv -f "$STATE_DIR/.pending-$$" "$PENDING"
  echo 'EVENT=CHANGED_REFRESH_REQUIRED'
  exit 0
fi
[ -f "$PENDING" ] && [ ! -L "$PENDING" ] || { echo 'HOLD=NO_PENDING_FINGERPRINT'; exit 2; }
[ "$(cat "$PENDING")" = "$new" ] || { echo 'HOLD=INPUT_CHANGED_WHILE_PROCESSING'; exit 2; }
if [ "$MODE" = fail ]; then
  printf '%s %s\n' "$new" "$now" > "$STATE_DIR/.failed-$$"
  mv -f "$STATE_DIR/.failed-$$" "$FAILED"
  echo 'REFRESH_EVENT=FAILED_NO_SUCCESS_MARKER'
  exit 0
fi
# ack means the original refresh already succeeded; ensure the active mobile cache
# includes nonempty SNI on every matching A01 AnyTLS node before recording success.
[ -f "$CACHE" ] && [ ! -L "$CACHE" ] && [ -s "$CACHE" ] || { echo 'HOLD=CACHE_NOT_AVAILABLE_FOR_ACK'; exit 2; }
if ! ruby - "$CACHE" <<'RUBY'
begin
  require 'psych'
  obj=Psych.safe_load(File.read(ARGV[0]), permitted_classes: [], permitted_symbols: [], aliases: true)
  proxies=obj.is_a?(Hash) ? obj['proxies'] : nil
  raise 'proxies' unless proxies.is_a?(Array) && proxies.size>0
  anytls=proxies.select { |p| p.is_a?(Hash) && p['type'].to_s.downcase=='anytls' }
  re=/(?:^|[^A-Za-z0-9])A[\s_-]*0?1(?=[^A-Za-z0-9]|$)/i
  a01=anytls.select { |p| re.match?(p['name'].to_s) }
  raise 'a01' if a01.empty?
  raise 'sni' if a01.any? { |p| p['sni'].to_s.strip.empty? }
  groups=obj['proxy-groups']
  raise 'groups' unless groups.is_a?(Array) && !groups.empty?
  puts 'OUTPUT_A01_SNI=PASS'
rescue StandardError
  puts 'OUTPUT_A01_SNI=HOLD'
  exit 1
end
RUBY
then
  echo 'HOLD=OUTPUT_VALIDATION_FAILED_NO_ACK'
  exit 2
fi
printf '%s\n' "$new" > "$STATE_DIR/.done-$$"
mv -f "$STATE_DIR/.done-$$" "$DONE"
rm -f "$FAILED" "$PENDING"
echo 'REFRESH_EVENT=COMMITTED_SUCCESS_FINGERPRINT'
