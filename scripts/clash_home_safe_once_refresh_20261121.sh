#!/bin/sh
# One-time, guarded renewal of the existing clash-home cached mobile YAML.
# Original refresh-current.sh and refresh.py are preserved and reused.
# Before: save old cache and confirm 18080 serves exactly that cache.
# After: require A01 AnyTLS SNI, preserved groups, real 18080 delivery.
# Failure: best-effort atomic restore of old cache (including on TERM/INT).
# Never prints URLs, passwords, nodes, original refresh logs or YAML.
set -eu
umask 077
ROOT='/mnt/sata1-4/clash-home'
CACHE="$ROOT/cache/merged.yaml"
NEW_ID='sha256:ce901e8d55821e510e3093d3da0bb05058ce6af1d55e5fe337c95dc0b8d77b45'
SAVE="$ROOT/sni-refresh-rollback-20261121"
LOCK="$ROOT/.sni-refresh-20261121.lock"
HTTP='http://127.0.0.1:18080/'
stage=0
passed=0

stop() { echo "HOLD: $1"; exit 1; }
if [ ! -d "$ROOT" ] || [ -L "$ROOT" ]; then stop 'expected clash-home directory unavailable'; fi
for c in docker curl ruby cp mv cmp mkdir rmdir chmod wc tr rm; do
  command -v "$c" >/dev/null 2>&1 || stop "command missing: $c"
done
[ -f "$ROOT/refresh-current.sh" ] && [ ! -L "$ROOT/refresh-current.sh" ] || stop 'original refresh entrypoint missing'
[ -f "$ROOT/refresh.py" ] && [ ! -L "$ROOT/refresh.py" ] || stop 'original Python generator missing'
[ -f "$CACHE" ] && [ ! -L "$CACHE" ] && [ -s "$CACHE" ] || stop 'active cached YAML missing/empty/symlink'
[ "$(wc -c < "$ROOT/refresh-current.sh" | tr -d ' ')" = 161 ] || stop 'refresh entrypoint changed since user screenshot'
[ "$(wc -c < "$ROOT/refresh.py" | tr -d ' ')" = 2710 ] || stop 'refresh.py changed since user screenshot'
[ "$(docker inspect -f '{{.State.Running}}|{{len .Mounts}}' clash-home 2>/dev/null)" = 'true|2' ] || stop 'clash-home running/mounts drift'
[ "$(docker inspect -f '{{.State.Running}}|{{.Image}}' nostalgic_pasteur 2>/dev/null)" = "true|$NEW_ID" ] || stop '25500 production image/running drift'
curl --noproxy '*' -fsS --connect-timeout 3 --max-time 6 http://127.0.0.1:25500/version >/dev/null || stop '25500 unavailable'

if [ -e "$SAVE" ] || [ -L "$SAVE" ]; then stop 'backup directory already exists; do not re-run'; fi
if [ -e "$LOCK" ] || [ -L "$LOCK" ]; then stop 'one-time lock already exists; do not re-run'; fi

mkdir "$LOCK" || stop 'cannot acquire one-time lock'
cleanup() {
  result=$?
  trap - EXIT HUP INT TERM
  set +e
  if [ "$stage" -eq 1 ] && [ "$passed" -eq 0 ]; then
    echo 'REFRESH_RESULT=HOLD_ROLLBACK_ATTEMPTED'
    if [ -f "$SAVE/merged.yaml.before" ]; then
      if ! cmp -s "$CACHE" "$SAVE/merged.yaml.before"; then
        cp -p "$SAVE/merged.yaml.before" "$ROOT/cache/.merged.yaml.restore-$$" &&
          mv -f "$ROOT/cache/.merged.yaml.restore-$$" "$CACHE" || echo 'ROLLBACK_WARNING=ATOMIC_RESTORE_FAILED'
      fi
      if cmp -s "$CACHE" "$SAVE/merged.yaml.before"; then
        echo 'ROLLBACK_RESULT=ORIGINAL_CACHE_PRESERVED_OR_RESTORED'
      else
        echo 'ROLLBACK_RESULT=HOLD_MANUAL_RECOVERY_NEEDED'
      fi
    else
      echo 'ROLLBACK_RESULT=HOLD_BACKUP_MISSING'
    fi
  fi
  rmdir "$LOCK" 2>/dev/null || echo 'LOCK_WARNING=MANUAL_REVIEW_REQUIRED'
  exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mkdir "$SAVE" || stop 'cannot create root-only backup directory'
chmod 700 "$SAVE" || stop 'cannot restrict backup directory'
cp -p "$CACHE" "$SAVE/merged.yaml.before" || stop 'cannot back up current YAML'
chmod 600 "$SAVE/merged.yaml.before" || stop 'cannot protect backup'
cmp -s "$CACHE" "$SAVE/merged.yaml.before" || stop 'backup checksum not matching'

curl --noproxy '*' -fsS --connect-timeout 3 --max-time 30 "$HTTP" -o "$SAVE/served.before" || stop 'cannot read live 18080 response'
cmp -s "$CACHE" "$SAVE/served.before" || stop '18080 not serving expected current cache'
rm -f "$SAVE/served.before"

ruby - "$CACHE" <<'RUBY'
begin
  require 'psych'
  data=Psych.safe_load(File.read(ARGV[0]), permitted_classes: [], permitted_symbols: [], aliases: true)
  tls=data.fetch('proxies').select{|p| p.is_a?(Hash)&&p['type'].to_s.downcase=='anytls'}
  a01=tls.select{|p| p['name'].to_s.match?(/(?:^|[^A-Za-z0-9])A[\s_-]*0?1(?=[^A-Za-z0-9]|$)/i)}
  absent=a01.count{|p| p['sni'].to_s.strip.empty?}
  puts "BEFORE_ANYTLS=#{tls.length} BEFORE_A01=#{a01.length} BEFORE_A01_MISSING_SNI=#{absent}"
  if a01.empty? || absent==0
    puts 'HOLD_CACHE_NOT_IN_EXPECTED_OLD_A01_STATE'
    exit 1
  end
rescue StandardError
  puts 'HOLD_BEFORE_CACHE_UNPARSEABLE'
  exit 1
end
RUBY

# Run original production entrypoint, not a new converter implementation.
# Its output and possible URL-bearing error messages remain private on disk.
stage=1
echo 'ORIGINAL_REFRESH=STARTED_PRIVATE_LOG'
if (cd "$ROOT" && sh ./refresh-current.sh > "$SAVE/refresh.log.private" 2>&1); then
  echo 'ORIGINAL_REFRESH_EXIT=0'
else
  echo 'HOLD_ORIGINAL_REFRESH_FAILED_CHECK_PRIVATE_LOG_ON_ROUTER'
  exit 1
fi
[ -s "$CACHE" ] && [ ! -L "$CACHE" ] || stop 'refresh yielded empty cache or symlink'

# Validate revised cache against backup before considering cutover successful.
ruby - "$SAVE/merged.yaml.before" "$CACHE" <<'RUBY'
begin
  require 'psych'
  old=Psych.safe_load(File.read(ARGV[0]), permitted_classes: [], permitted_symbols: [], aliases: true)
  cur=Psych.safe_load(File.read(ARGV[1]), permitted_classes: [], permitted_symbols: [], aliases: true)
  raise 'no proxy lists' unless old['proxies'].is_a?(Array)&&cur['proxies'].is_a?(Array)
  counts=->(obj) do
    tls=obj.fetch('proxies').select{|p| p.is_a?(Hash)&&p['type'].to_s.downcase=='anytls'}
    a01=tls.select{|p| p['name'].to_s.match?(/(?:^|[^A-Za-z0-9])A[\s_-]*0?1(?=[^A-Za-z0-9]|$)/i)}
    [obj.fetch('proxies').length,tls.length,a01.length,a01.count{|p| p['sni'].to_s.strip.empty?}]
  end
  a=counts.call(old); b=counts.call(cur)
  puts "AFTER_PROXIES=#{b[0]} AFTER_ANYTLS=#{b[1]} AFTER_A01=#{b[2]} AFTER_A01_MISSING_SNI=#{b[3]}"
  if b[2]<a[2] || b[2]==0 || b[3]!=0 || b[0]<a[0]*0.8 || b[1]<a[1]*0.8
    puts 'HOLD_NEW_CACHE_A01_SNI_OR_NODE_COUNT_FAILED'
    exit 1
  end
  old_groups=(old['proxy-groups']||[]).select{|g|g.is_a?(Hash)}.map{|g|g['name']}.compact
  new_groups=(cur['proxy-groups']||[]).select{|g|g.is_a?(Hash)}.map{|g|g['name']}.compact
  if old_groups.empty? || (old_groups-new_groups).any?
    puts 'HOLD_NEW_CACHE_LOST_OLD_PROXY_GROUPS'
    exit 1
  end
  puts 'NEW_CACHE_A01_SNI_AND_GROUPS=PASS'
rescue StandardError
  puts 'HOLD_NEW_CACHE_UNREADABLE'
  exit 1
end
RUBY

curl --noproxy '*' -fsS --connect-timeout 3 --max-time 30 "$HTTP" -o "$SAVE/served.after" || stop 'cannot read 18080 after refresh'
cmp -s "$CACHE" "$SAVE/served.after" || stop '18080 delivered bytes differ from refreshed cache'
rm -f "$SAVE/served.after"
[ "$(docker inspect -f '{{.State.Running}}' clash-home 2>/dev/null)" = true ] || stop 'clash-home stopped'
passed=1
echo 'MOBILE_18080_NEW_CACHE=PASS_EXACT_LIVE_DELIVERY'
echo "BACKUP_DIR=$SAVE"
echo 'MOBILE_REFRESH_RESULT=PASS_A01_SNI_FIXED_IN_18080'
echo 'CLASHMATE_A01_REAL_CONNECTION=NOT_YET_VERIFIED'
