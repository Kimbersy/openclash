#!/bin/sh
# iStoreOS/ClashMate post-install, read-only status in a few lines.
# No modification, re-run, cleanup of production files, or secret output.
set -eu
umask 077
BASE='/mnt/sata1-4/clash-home'
REF='MOBILE_CONVERTER_IMAGE_WATCH_V1'
WATCH="$BASE/watch-clash-li.sh"
ACK="$BASE/.last_mobile_converter_image_id"
RETRY="$BASE/.last_mobile_converter_retry"
EXPECTED='sha256:ce901e8d55821e510e3093d3da0bb05058ce6af1d55e5fe337c95dc0b8d77b45'
command -v curl >/dev/null 2>&1 || { echo 'HOLD=CURL_MISSING'; exit 1; }
command -v ruby >/dev/null 2>&1 || { echo 'HOLD=RUBY_MISSING'; exit 1; }
command -v docker >/dev/null 2>&1 || { echo 'HOLD=DOCKER_MISSING'; exit 1; }
[ -f "$WATCH" ] && [ ! -L "$WATCH" ] || { echo 'HOLD=WATCH_MISSING'; exit 1; }
if grep -Fq "$REF" "$WATCH"; then
  echo 'WATCH_PATCH=INSTALLED'
else
  echo 'WATCH_PATCH=NOT_FOUND'
  exit 1
fi
CURRENT=$(docker inspect -f '{{.Image}}' nostalgic_pasteur 2>/dev/null) || {
  echo 'HOLD=CONVERTER_NOT_RUNNING_OR_MISSING'
  exit 1
}
if [ "$CURRENT" = "$EXPECTED" ]; then
  echo 'CONVERTER_IMAGE=EXPECTED'
else
  echo 'CONVERTER_IMAGE=CHANGED'
fi
if [ -f "$ACK" ] && [ ! -L "$ACK" ] && [ "$(cat "$ACK")" = "$CURRENT" ]; then
  echo 'IMAGE_CHANGE_REFRESH_ACK=PASS'
else
  echo 'IMAGE_CHANGE_REFRESH_ACK=PENDING_OR_FAILED'
fi
if [ -f "$RETRY" ] && [ ! -L "$RETRY" ]; then
  echo 'IMAGE_CHANGE_RETRY_MARKER=PRESENT'
else
  echo 'IMAGE_CHANGE_RETRY_MARKER=ABSENT'
fi
WORK="/tmp/clash-mobile-postverify-$$"
mkdir "$WORK" || { echo 'HOLD=TEMP_UNAVAILABLE'; exit 1; }
chmod 700 "$WORK"
trap 'rm -f "$WORK/mobile.yaml"; rmdir "$WORK" 2>/dev/null || true' EXIT
trap 'exit 1' HUP INT TERM
if ! curl --noproxy '*' -fsS --connect-timeout 3 --max-time 30 \
    'http://127.0.0.1:18080/' -o "$WORK/mobile.yaml"; then
  echo 'MOBILE_18080=HTTP_FAILED'
  exit 1
fi
ruby - "$WORK/mobile.yaml" <<'RUBY'
begin
  require 'psych'
  cfg=Psych.safe_load(File.read(ARGV[0]),permitted_classes:[],permitted_symbols:[],aliases:true)
  all=cfg.is_a?(Hash) ? cfg['proxies'] : nil
  raise 'no proxy list' unless all.is_a?(Array)
  anytls=all.select{|p| p.is_a?(Hash)&&p['type'].to_s.downcase=='anytls'}
  a01=anytls.select{|p| p['name'].is_a?(String) && /(?:^|[^A-Za-z0-9])A[\s_-]*0?1(?=[^A-Za-z0-9]|$)/i.match?(p['name'])}
  missing=a01.count{|p| p['sni'].to_s.strip.empty?}
  puts 'MOBILE_18080=YAML_OK'
  puts "A01_ANYTLS_TOTAL=#{a01.length}"
  puts "A01_MISSING_SNI=#{missing}"
  puts(a01.length>0 && missing==0 ? 'MOBILE_A01_SNI=PASS' : 'MOBILE_A01_SNI=NOT_YET_PASS')
rescue StandardError
  puts 'MOBILE_18080=YAML_PARSE_HOLD'
  exit 1
end
RUBY
echo 'POST_INSTALL_CHECK=READ_ONLY'
