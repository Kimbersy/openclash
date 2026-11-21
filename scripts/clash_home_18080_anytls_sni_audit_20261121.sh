#!/bin/sh
# Read-only end-to-end check of the YAML currently served for ClashMate.
# Reads only 127.0.0.1:18080/ and prints counts; never exposes proxy names,
# servers, node passwords, subscription tokens, or response body.
set -eu
umask 077
for c in docker curl ruby mkdir rm rmdir; do
  command -v "$c" >/dev/null 2>&1 || { echo "HOLD_MISSING_COMMAND=$c"; exit 1; }
done

docker inspect -f 'MOBILE_18080_CONTAINER_RUNNING={{.State.Running}} MOBILE_PORT_BINDINGS={{json .HostConfig.PortBindings}}' clash-home 2>/dev/null || {
  echo 'HOLD_CLASH_HOME_CONTAINER_NOT_FOUND'
  exit 1
}

WORK="/tmp/clash-home-sni-audit-$$"
mkdir "$WORK" || { echo 'HOLD_CANNOT_CREATE_TEMP_DIRECTORY'; exit 1; }
trap 'rm -f "$WORK/response.yaml"; rmdir "$WORK" 2>/dev/null || true' EXIT
trap 'exit 1' HUP INT TERM

if ! curl --noproxy '*' -fsS --connect-timeout 4 --max-time 35 \
  http://127.0.0.1:18080/ -o "$WORK/response.yaml"; then
  echo 'HOLD_MOBILE_18080_HTTP_UNAVAILABLE'
  exit 1
fi

ruby - "$WORK/response.yaml" <<'RUBY'
begin
  require 'psych'
  data = Psych.safe_load(File.read(ARGV[0]), permitted_classes: [], permitted_symbols: [], aliases: true)
rescue StandardError
  puts 'HOLD_MOBILE_RESPONSE_NOT_PARSEABLE_YAML'
  exit 1
end
unless data.is_a?(Hash) && data['proxies'].is_a?(Array)
  puts 'HOLD_MOBILE_RESPONSE_NO_PROXY_ARRAY'
  exit 1
end

nodes = data['proxies'].select { |p| p.is_a?(Hash) }
anytls = nodes.select { |p| p['type'].to_s.downcase == 'anytls' }
a01rx = /(?:^|[^A-Za-z0-9])A[\s_-]*0?1(?=[^A-Za-z0-9]|$)/i
usrx = /(美国|美國|美区|美區|🇺🇸|\bUS\b|\bUSA\b|United[ -]?States|America)/i
sni = ->(p) { p['sni'].is_a?(String) && !p['sni'].strip.empty? }
a01 = anytls.select { |p| p['name'].is_a?(String) && a01rx.match?(p['name']) }
us = anytls.select { |p| p['name'].is_a?(String) && usrx.match?(p['name']) }
missing = ->(arr) { arr.count { |p| !sni.call(p) } }

puts "MOBILE_PROXY_TOTAL=#{nodes.length}"
puts "MOBILE_ANYTLS_TOTAL=#{anytls.length}"
puts "MOBILE_ANYTLS_MISSING_SNI=#{missing.call(anytls)}"
puts "MOBILE_A01_ANYTLS_TOTAL=#{a01.length}"
puts "MOBILE_A01_MISSING_SNI=#{missing.call(a01)}"
puts "MOBILE_US_ANYTLS_TOTAL=#{us.length}"
puts "MOBILE_US_MISSING_SNI=#{missing.call(us)}"
if a01.length > 0
  puts "MOBILE_A01_SNI_RESULT=#{missing.call(a01) == 0 ? 'PASS_PRESENT' : 'FAIL_MISSING'}"
elsif us.length > 0
  puts 'MOBILE_A01_SNI_RESULT=HOLD_A01_NAME_NOT_MATCHED'
else
  puts 'MOBILE_A01_SNI_RESULT=HOLD_NO_MATCHED_US_A01_ANYTLS'
end
puts 'MOBILE_18080_RESPONSE=YAML_PARSED_NO_SECRETS_PRINTED'
RUBY
