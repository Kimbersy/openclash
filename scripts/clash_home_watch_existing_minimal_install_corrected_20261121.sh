#!/bin/sh
# Fixed one-time installer for the EXISTING clash-home watcher, not a new monitor.
# Only: converter image version change -> existing refresh flow. Original cron preserved.
set -eu
umask 077
BASE=/mnt/sata1-4/clash-home
LIVE="$BASE/watch-clash-li.sh"
BAKDIR="$BASE/.watch-source-backup-20261121"
BACKUP="$BAKDIR/watch-clash-li.sh.before"
CAND="$BASE/.watch-clash-li.candidate-20261121-$$"
trap 'rm -f "$CAND"' EXIT
REF='MOBILE_CONVERTER_IMAGE_WATCH_V1'

hold() { echo "HOLD=$1"; exit 1; }
for c in ruby sh cp mv chmod mkdir docker curl stat rm cmp grep; do command -v "$c" >/dev/null 2>&1 || hold "DEPENDENCY_$c"; done
[ -d "$BASE" ] && [ ! -L "$BASE" ] || hold BASE_NOT_FOUND
[ -f "$LIVE" ] && [ ! -L "$LIVE" ] || hold WATCH_NOT_FOUND
[ -f "$BASE/refresh.py" ] && [ -f "$BASE/refresh-current.sh" ] || hold ORIGINAL_REFRESH_MISSING
[ ! -e "$BAKDIR" ] && [ ! -L "$BAKDIR" ] || hold ALREADY_STAGED_DO_NOT_RERUN
[ "$(docker inspect -f '{{.State.Running}}' clash-home 2>/dev/null)" = true ] || hold CLASH_HOME_DOWN
[ "$(docker inspect -f '{{.Image}}' nostalgic_pasteur 2>/dev/null)" = 'sha256:ce901e8d55821e510e3093d3da0bb05058ce6af1d55e5fe337c95dc0b8d77b45' ] || hold CONVERTER_IMAGE_DRIFT
if grep -Fq "$REF" "$LIVE"; then hold WATCH_ALREADY_PATCHED; fi

# Before ANY changes, inspect the exact known production structure.
# The source is parsed locally; it is never printed or uploaded.
if ! ruby - "$LIVE" "$CAND" <<'RUBY_PATCH'
path,candidate=ARGV
lines=File.binread(path).lines
expected={34=>/^\s*NEED_REFRESH=0\s*$/,52=>/^\s*NEED_REFRESH=1\s*$/,
 105=>/NEED_REFRESH/,118=>/refresh-current\.sh/,119=>/^\s*RC=\$\?\s*$/,
 121=>/^\s*if\s+.*\$\{?RC\}?.*-eq\s+0\s*\]/}
unless File.size(path)==3310 && lines.size==146 && expected.all?{|n,re| re.match?(lines[n-1])}
 puts 'HOLD=WATCH_CONTRACT_CHANGED_NO_PATCH'; exit 1
end
# The original source has a single existing lock and refresh call.
unless lines[14].include?('LOCK=') && lines[22].match?(/^\s*if\b/) &&
       lines[31].include?('trap') &&
       lines[104].match?(/NEED_REFRESH/) && lines[104].match?(/-eq\s+0/) &&
       lines[104].match?(/\bexit\s+0\b/) && lines[120].include?('RC')
 puts 'HOLD=WATCH_LOCK_OR_BRANCH_NOT_AS_EXPECTED'; exit 1
end
# Strictly insert inside the original watcher before its NEED_REFRESH decision.
before = <<'SHELL_CODE'
# MOBILE_CONVERTER_IMAGE_WATCH_V1 START -- kept inside existing watcher/lock.
CONVERTER_TRIGGER=0
CONVERTER_IMAGE=$(docker inspect -f '{{.Image}}' nostalgic_pasteur 2>/dev/null || true)
CONVERTER_STATE="$BASE/.last_mobile_converter_image_id"
CONVERTER_RETRY="$BASE/.last_mobile_converter_retry"
CONVERTER_BACKUP_DIR="$BASE/.mobile-converter-rollback"
CONVERTER_BACKUP="$CONVERTER_BACKUP_DIR/merged.yaml.before"
if [ -n "$CONVERTER_IMAGE" ] && [ "$(cat "$CONVERTER_STATE" 2>/dev/null || true)" != "$CONVERTER_IMAGE" ]; then
    LAST_RETRY=$(cat "$CONVERTER_RETRY" 2>/dev/null || echo 0)
    case "$LAST_RETRY" in ''|*[!0-9]*) LAST_RETRY=0 ;; esac
    NOW_TS=$(date +%s)
    if [ "$NOW_TS" -ge "$LAST_RETRY" ] && [ $((NOW_TS - LAST_RETRY)) -ge 3600 ]; then
        NEED_REFRESH=1
        CONVERTER_TRIGGER=1
    fi
fi
# MOBILE_CONVERTER_IMAGE_WATCH_V1 END CHECK
SHELL_CODE
backup = <<'SHELL_CODE'
# MOBILE_CONVERTER_IMAGE_WATCH_V1 backup before existing atomic refresh.
if [ "$CONVERTER_TRIGGER" -eq 1 ]; then
    [ -f "$BASE/cache/merged.yaml" ] && [ ! -L "$BASE/cache/merged.yaml" ] || exit 1
    mkdir -p "$CONVERTER_BACKUP_DIR" && chmod 700 "$CONVERTER_BACKUP_DIR" || exit 1
    cp -p "$BASE/cache/merged.yaml" "$CONVERTER_BACKUP" || exit 1
fi
SHELL_CODE
# On the first successful run after an image change validate real mobile A01 SNI;
# on invalid converter output restore the previous mobile cache and do NOT ack.
after = <<'SHELL_CODE'
# MOBILE_CONVERTER_IMAGE_WATCH_V1 validate/ack or restore.
if [ "$CONVERTER_TRIGGER" -eq 1 ]; then
    SNI_VALID=0
    if [ "$RC" -eq 0 ] && ruby - "$BASE/cache/merged.yaml" <<'RUBY_SNI'
begin
  require 'psych'
  data=Psych.safe_load(File.read(ARGV[0]),permitted_classes:[],permitted_symbols:[],aliases:true)
  nodes=data.is_a?(Hash) ? data['proxies'] : nil
  raise 'nodes' unless nodes.is_a?(Array)
  a01=nodes.select { |p| p.is_a?(Hash) && p['type'].to_s.downcase=='anytls' && /(?:^|[^A-Za-z0-9])A[\s_-]*0?1(?=[^A-Za-z0-9]|$)/i.match?(p['name'].to_s) }
  raise 'a01' if a01.empty? || a01.any? { |p| p['sni'].to_s.strip.empty? }
rescue StandardError
  exit 1
end
RUBY_SNI
    then SNI_VALID=1; fi
    if [ "$SNI_VALID" -eq 1 ]; then
        if printf '%s\n' "$CONVERTER_IMAGE" > "$CONVERTER_STATE.tmp" && mv -f "$CONVERTER_STATE.tmp" "$CONVERTER_STATE"; then
            rm -f "$CONVERTER_RETRY"
            echo 'MOBILE_CONVERTER_AUTO_REFRESH=PASS_A01_SNI' >> "$LOG"
        else
            echo 'MOBILE_CONVERTER_AUTO_REFRESH=HOLD_MARKER_WRITE_FAILED' >> "$LOG"
            RC=1
        fi
    else
        if cp -p "$CONVERTER_BACKUP" "$BASE/cache/.merged.yaml.restore-$$" && mv -f "$BASE/cache/.merged.yaml.restore-$$" "$BASE/cache/merged.yaml"; then
            echo 'MOBILE_CONVERTER_AUTO_REFRESH=HOLD_ORIGINAL_CACHE_RESTORED' >> "$LOG"
        else
            echo 'MOBILE_CONVERTER_AUTO_REFRESH=HOLD_MANUAL_CACHE_RESTORE_REQUIRED' >> "$LOG"
        fi
        printf '%s\n' "$(date +%s)" > "$CONVERTER_RETRY"
        RC=1
    fi
fi
# MOBILE_CONVERTER_IMAGE_WATCH_V1 END
SHELL_CODE

patched = String.new
lines.each_with_index do |line,i|
 patched << before if i==104
 patched << backup if i==117
 patched << line
 patched << after if i==118
end
File.binwrite(candidate,patched)
puts 'SOURCE_PATCH=EXACT_ANCHORS_PASS'
RUBY_PATCH
then hold WATCH_SOURCE_PATCH_REJECTED; fi

# Reject syntax errors before touching live source.
sh -n "$LIVE" || hold ORIGINAL_SHELL_SYNTAX
sh -n "$CAND" || hold CANDIDATE_SHELL_SYNTAX
[ ! -e "$BAKDIR" ] || hold BACKUP_RACE
mkdir "$BAKDIR" || hold BACKUP_CREATE
chmod 700 "$BAKDIR" || hold BACKUP_PERMISSIONS
cp -p "$LIVE" "$BACKUP" || hold BACKUP_COPY
cmp -s "$LIVE" "$BACKUP" || hold BACKUP_MISMATCH
ORIGINAL_MODE=$(stat -c %a "$LIVE") || hold SOURCE_MODE_UNAVAILABLE
chmod "$ORIGINAL_MODE" "$CAND" || hold CANDIDATE_MODE_ERROR
# The original script file remains unchanged until the single rename.
if mv -f "$CAND" "$LIVE"; then
  sh -n "$LIVE" || { cp -p "$BACKUP" "$LIVE"; hold LIVE_SYNTAX_FAILED_RESTORED; }
  echo 'INSTALL_RESULT=PASS_EXISTING_WATCH_MINIMAL_PATCH_APPLIED'
  echo 'EXISTING_0430_REFRESH=UNCHANGED'
  echo 'CACHE_AT_INSTALL=NOT_REGENERATED'
  echo 'NEXT_NATURAL_WATCH=AUTOMATIC_REFRESH_IF_IMAGE_CHANGE'
  echo 'MOBILE_A01_SNI=BUSINESS_VERIFICATION_PENDING'
else
  hold ATOMIC_SWITCH_FAILED_BACKUP_RETAINED
fi
