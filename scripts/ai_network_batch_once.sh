#!/bin/sh
# Bounded ordinal sample (START..START+COUNT-1) from all 58 live subscription nodes.
# Only HTTP website transport hints; no AI login and no production group changes.
# No login check, no parent group change, no API request to the production core.
set -u
umask 077
CORE=/etc/openclash/core/clash_meta
START=${START:-1}
COUNT=${COUNT:-3}
case "$START:$COUNT" in
  *[!0-9:]*|:*|*:) echo 'BATCH=BLOCKED INVALID_RANGE'; exit 1 ;;
esac
if [ "$START" -lt 1 ] || [ "$COUNT" -lt 1 ] || [ "$COUNT" -gt 4 ] || [ "$START" -gt 58 ] || [ $((START+COUNT-1)) -gt 58 ]; then
  echo 'BATCH=BLOCKED OUT_OF_RANGE'; exit 1
fi
classify_http() {
  rc="$1"; code="$2"
  if [ "$rc" -eq 0 ]; then
    case "$code" in
      2??|3??) echo HTTP_COMPLETE ;;
      403|451) echo HTTP_DENIED ;;
      429) echo HTTP_RATE_LIMIT ;;
      5??) echo HTTP_SERVER_ERROR ;;
      *) echo HTTP_OTHER_COMPLETE ;;
    esac
  else
    case "$rc" in
      28) if [ "$code" = 000 ]; then echo TIMEOUT_NO_HTTP; else echo HTTP_INCOMPLETE_TIMEOUT; fi ;;
      35|60) echo TLS_ERROR ;;
      *) if [ "$code" = 000 ]; then echo TRANSPORT_ERROR; else echo HTTP_INCOMPLETE_ERROR; fi ;;
    esac
  fi
}
geo_diagnostic() {
  r1="$1";r2="$2";c1="$3";ip1="$4";c2="$5";ip2="$6"
  if [ "$r1" -ne 0 ] && [ "$r2" -ne 0 ]; then echo BOTH_GEO_FETCH_FAILED;return;fi
  if [ "$r1" -ne 0 ]; then echo IPINFO_FETCH_FAILED;return;fi
  if [ "$r2" -ne 0 ]; then echo CLOUDFLARE_FETCH_FAILED;return;fi
  case "$c1" in
    [A-Z][A-Z]) : ;;
    *) echo IPINFO_PARSE_FAILED;return ;;
  esac
  case "$ip1" in
    *.*.*.*) : ;;
    *) echo IPINFO_PARSE_FAILED;return ;;
  esac
  case "$c2" in
    [A-Z][A-Z]) : ;;
    *) echo CLOUDFLARE_PARSE_FAILED;return ;;
  esac
  case "$ip2" in
    *.*.*.*) : ;;
    *) echo CLOUDFLARE_NON_IPV4_OR_PARSE_FAILED;return ;;
  esac
  if [ "$ip1" != "$ip2" ]; then echo IPV4_MISMATCH;return;fi
  if [ "$c1" != "$c2" ]; then echo COUNTRY_MISMATCH;return;fi
  echo MATCH
}
if [ "${TEST_GEO_CLASSIFIER:-0}" = 1 ]; then
  [ "$(geo_diagnostic 0 0 GB 198.51.100.1 GB 198.51.100.1)" = MATCH ] &&
  [ "$(geo_diagnostic 28 0 '' '' GB 198.51.100.1)" = IPINFO_FETCH_FAILED ] &&
  [ "$(geo_diagnostic 0 28 GB 198.51.100.1 '' '')" = CLOUDFLARE_FETCH_FAILED ] &&
  [ "$(geo_diagnostic 28 28 '' '' '' '')" = BOTH_GEO_FETCH_FAILED ] &&
  [ "$(geo_diagnostic 0 0 '' '' GB 198.51.100.1)" = IPINFO_PARSE_FAILED ] &&
  [ "$(geo_diagnostic 0 0 GB 198.51.100.1 '' '')" = CLOUDFLARE_PARSE_FAILED ] &&
  [ "$(geo_diagnostic 0 0 GB 198.51.100.1 GB 2001:db8::1)" = CLOUDFLARE_NON_IPV4_OR_PARSE_FAILED ] &&
  [ "$(geo_diagnostic 0 0 GB 198.51.100.1 US 198.51.100.1)" = COUNTRY_MISMATCH ] &&
  [ "$(geo_diagnostic 0 0 GB 198.51.100.1 GB 198.51.100.2)" = IPV4_MISMATCH ] &&
  { echo 'GEO_CLASSIFIER_TEST=PASS';exit 0; }
  echo 'GEO_CLASSIFIER_TEST=FAIL';exit 1
fi
if [ "${TEST_CLASSIFIER:-0}" = 1 ]; then
  [ "$(classify_http 0 200)" = HTTP_COMPLETE ] &&
  [ "$(classify_http 28 200)" = HTTP_INCOMPLETE_TIMEOUT ] &&
  [ "$(classify_http 28 000)" = TIMEOUT_NO_HTTP ] &&
  [ "$(classify_http 60 000)" = TLS_ERROR ] &&
  [ "$(classify_http 0 301)" = HTTP_COMPLETE ] &&
  [ "$(classify_http 0 429)" = HTTP_RATE_LIMIT ] &&
  { echo 'CLASSIFIER_TEST=PASS'; exit 0; }
  echo 'CLASSIFIER_TEST=FAIL'; exit 1
fi
if [ ! -x "$CORE" ] || ! command -v ruby >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo 'BATCH=BLOCKED REASON=TOOLS'; exit 1
fi
run_one() (
  idx="$1"
  tag="NODE_$(printf '%02d' "$idx")"
  D="/tmp/openclash-ai-batch-$idx-$(date +%s)-$(ruby -e 'print Process.pid')"
  if ! mkdir -m 700 "$D" 2>/dev/null; then echo "$tag PREP=FAIL"; exit 1; fi
  pid=''
  watch=''
  stop="$D/watchdog.stop"
  owned() {
    [ -n "$pid" ] && ruby -e 'begin;v=File.binread("/proc/#{ARGV[0]}/cmdline").split("\0");exit(v.include?(ARGV[1]) ? 0 : 1);rescue StandardError;exit 1;end' "$pid" "$D/isolated.yaml"
  }
  port_free() {
    ruby -e 'begin;b=%w[/proc/net/tcp /proc/net/tcp6].any?{|p|File.file?(p)&&File.readlines(p).drop(1).any?{|l|c=l.split;c.size>3&&c[3]=="0A"&&c[1].split(":").last.to_i(16)==17881}};exit(b ? 1 : 0);rescue StandardError;exit 1;end'
  }
  cleanup() {
    trap - EXIT HUP INT TERM
    if owned; then kill -TERM "$pid" 2>/dev/null || :; fi
    sleep 1
    if owned; then kill -KILL "$pid" 2>/dev/null || :; fi
    : > "$stop"
    if [ -n "$watch" ]; then wait "$watch" 2>/dev/null || :; fi
    if [ -n "$pid" ]; then wait "$pid" 2>/dev/null || :; fi
    if owned || ! port_free; then
      echo "$tag CLEANUP=FAIL CORE_OR_PORT_REQUIRES_REVIEW"
      exit 92
    fi
    if ruby - "$D" <<'RUBY_CLEAN'
begin
  d=ARGV.fetch(0)
  raise unless %r{\A/tmp/openclash-ai-batch-\d+-\d+-\d+\z}.match?(d)
  st=File.lstat(d)
  raise unless st.directory? && st.uid==Process.euid && (st.mode&0077)==0
  walk=lambda do |dir|
    Dir.entries(dir).each do |name|
      next if name=='.'||name=='..'
      p=File.join(dir,name)
      f=File.lstat(p)
      if f.directory?
        walk.call(p)
        Dir.rmdir(p)
      elsif f.file? || f.symlink?
        File.unlink(p)
      else
        raise 'unexpected_entry'
      end
    end
  end
  walk.call(d)
  Dir.rmdir(d)
rescue StandardError
  exit 1
end
RUBY_CLEAN
    then
      echo "$tag CLEANUP=PASS CORE_EXIT=YES PORT_FREE=YES PRIVATE_FILES=REMOVED"
    else
      echo "$tag CLEANUP=FAIL PRIVATE_FILES_REMAIN"
      exit 93
    fi
  }
  trap cleanup EXIT
  trap 'exit 130' HUP INT TERM
  if ! port_free; then echo "$tag PREP=BLOCKED PORT_17881_IN_USE"; exit 1; fi
  ruby -rpsych - "$idx" "$D" <<'RUBY_PREP'
# encoding: UTF-8
begin
  idx=Integer(ARGV.fetch(0));d=ARGV.fetch(1)
  raise unless idx.between?(1,58)
  source=IO.popen(['uci','-q','get','openclash.config.config_path'],err:File::NULL){|io|io.read.to_s.strip}
  raise if source.empty?
  src=File.expand_path(source.start_with?('/') ? source : File.join('/etc/openclash/config',source))
  raise unless Dir['/etc/openclash/config/*.{yaml,yml}'].map{|p|File.expand_path(p)}.include?(src)
  raw=File.binread(src)
  raise unless raw.bytesize.between?(1,12_000_000)
  c=Psych.safe_load(raw,aliases:false)
  ps=c.fetch('proxies')
  raise unless ps.is_a?(Array) && ps.size==58 && ps.all?{|n|n.is_a?(Hash)&&n['name'].is_a?(String)&&n['type'].is_a?(String)}
  raise unless ps.map{|n|n['name']}.uniq.size==ps.size
  begin
    digest=IO.popen(['sha256sum',src],err:File::NULL){|io|io.read.to_s.split.first}
    fingerprint=digest.to_s.match?(/\A[0-9a-f]{64}\z/) ? digest[0,16] : 'UNAVAILABLE'
  rescue StandardError
    fingerprint='UNAVAILABLE'
  end
  puts "SOURCE_SNAPSHOT_SHA256_PREFIX16=#{fingerprint}"
  sample=ps[idx-1]
  raise unless sample
  if sample['dialer-proxy'] || %w[direct reject reject-drop pass compatible].include?(sample['type'].downcase)
    puts "NODE_#{'%02d'%idx} PREP=SKIP_DEPENDENT_OR_BUILTIN"
    exit 3
  end
  cfg={'allow-lan'=>false,'mode'=>'rule','log-level'=>'silent',
     'port'=>0,'socks-port'=>0,'mixed-port'=>0,'redir-port'=>0,'tproxy-port'=>0,
     'external-controller'=>'','tun'=>{'enable'=>false},
     'profile'=>{'store-selected'=>false,'store-fake-ip'=>false},'proxies'=>[sample],
     'listeners'=>[{'name'=>'audit-only','type'=>'http','listen'=>'127.0.0.1',
                    'port'=>17881,'proxy'=>sample['name']}],'rules'=>['MATCH,REJECT']}
  File.open(File.join(d,'isolated.yaml'),File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(Psych.dump(cfg))}
  raise unless File.binread(src)==raw
  puts "NODE_#{'%02d'%idx} PREP=PASS CURRENT_NODES=#{ps.size} ISOLATED=YES"
rescue StandardError
  puts "NODE_#{ARGV[0]} PREP=BLOCKED"
  exit 1
end
RUBY_PREP
  prep_rc=$?
  if [ "$prep_rc" -eq 3 ]; then echo "$tag QUALIFICATION=SKIPPED_UNSUPPORTED";exit 0;fi
  if [ "$prep_rc" -ne 0 ]; then exit 1;fi
  if ! "$CORE" -t -d "$D" -f "$D/isolated.yaml" >"$D/core-config-test.log" 2>&1; then
    echo "$tag CORE_CONFIG=FAIL";exit 1
  fi
  if ! port_free; then echo "$tag CORE_START=BLOCKED PORT_BUSY";exit 1;fi
  (exec "$CORE" -d "$D" -f "$D/isolated.yaml") >"$D/core.log" 2>&1 &
  pid=$!
  sh -c '
    trap "" HUP
    pid=$1; conf=$2; stop=$3
    n=0
    while [ "$n" -lt 80 ]; do [ -f "$stop" ] && exit 0; sleep 1; n=$((n+1)); done
    ours() {
      ruby -e '\''begin;a=File.binread("/proc/#{ARGV[0]}/cmdline").split("\0");exit(a.include?(ARGV[1]) ? 0 : 1);rescue StandardError;exit 1;end'\'' "$pid" "$conf"
    }
    if ours; then kill -TERM "$pid" 2>/dev/null || :; fi
    sleep 2
    if ours; then kill -KILL "$pid" 2>/dev/null || :; fi
  ' watchdog "$pid" "$D/isolated.yaml" "$stop" </dev/null >"$D/watchdog.log" 2>&1 &
  watch=$!
  sleep 3
  if ! owned; then echo "$tag PILOT=FAIL CORE_NOT_RUNNING";exit 1;fi

  # Two independent IPv4 country observations. Do not publish actual egress IPs.
  ipjson=$(curl -4 --proxy http://127.0.0.1:17881 -sS --connect-timeout 3 --max-time 7 https://ipinfo.io/json 2>"$D/ipinfo.err")
  rc1=$?
  cftrace=$(curl -4 --proxy http://127.0.0.1:17881 -sS --connect-timeout 3 --max-time 7 https://www.cloudflare.com/cdn-cgi/trace 2>"$D/cloudflare.err")
  rc2=$?
  ipdata=$(printf '%s' "$ipjson" | ruby -rpsych -e 'begin;h=Psych.safe_load(STDIN.read,aliases:false);c=h["country"].to_s;i=h["ip"].to_s;print "#{c}|#{i}" if c.match?(/\A[A-Z]{2}\z/) && i.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/);rescue StandardError;end')
  ipcc=$(printf '%s' "$ipdata" | cut -d'|' -f1)
  ipv4=$(printf '%s' "$ipdata" | cut -d'|' -f2)
  cfcc=$(printf '%s\n' "$cftrace" | sed -n 's/^loc=//p' | head -n 1)
  cfip=$(printf '%s\n' "$cftrace" | sed -n 's/^ip=//p' | head -n 1)
  geo_reason=$(geo_diagnostic "$rc1" "$rc2" "$ipcc" "$ipv4" "$cfcc" "$cfip")
  if [ "$geo_reason" = MATCH ]; then
    echo "$tag EXIT_COUNTRY=$ipcc GEO_SOURCES=AGREE IPV4_MATCH=YES GEO_DIAG=MATCH"
  else
    echo "$tag EXIT_COUNTRY=UNVERIFIED GEO_SOURCES=INCOMPLETE_OR_CONFLICT GEO_DIAG=$geo_reason"
  fi

  for svc in CHATGPT GEMINI NOTEBOOKLM; do
    case "$svc" in
      CHATGPT) url=https://chatgpt.com/ ;;
      GEMINI) url=https://gemini.google.com/ ;;
      NOTEBOOKLM) url=https://notebooklm.google.com/ ;;
    esac
    if [ "$svc" = NOTEBOOKLM ]; then
      # Follow at most five HTTPS redirects via the SAME isolated proxy.
      # Keep redirect locations and effective URL only in private files, never terminal.
      result=$(curl -4 --noproxy '' -sS --proxy http://127.0.0.1:17881 \
        --connect-timeout 4 --max-time 15 -L --max-redirs 5 --proto-redir '=https' \
        -D "$D/notebooklm.headers" -o /dev/null \
        -w '%{http_code} %{time_starttransfer} %{time_total} %{size_download} %{num_redirects} %{url_effective}' \
        "$url" 2>"$D/$svc.curl.log")
      rc=$?
      printf '%s' "$result" >"$D/notebooklm.metadata"
      code=${result%% *}
      rest=${result#* }
      ttfb=${rest%% *}
      rest=${rest#* }
      total=${rest%% *}
      rest=${rest#* }
      bytes=${rest%% *}
      decision=$(ruby - "$D/notebooklm.headers" "$D/notebooklm.metadata" "$rc" <<'RUBY_NOTEBOOK'
# Read redirect chain for a known access gate, but never print URLs or tokens.
begin
  header,metadata,rcstr=ARGV
  raise unless File.file?(header) && File.size(header)<200_000
  raise unless File.file?(metadata) && File.size(metadata)<16_000
  h=File.binread(header)
  code,ttfb,total,bytes,hops,effective=File.binread(metadata).split(' ',6)
  raise unless code.to_s.match?(/\A\d{3}\z/) && hops.to_s.match?(/\A\d+\z/)
  rc=Integer(rcstr)
  urls=h.lines.grep(/\Alocation\s*:/i).map{|l|l.sub(/\Alocation\s*:\s*/i,'').strip}
  urls << effective.to_s.strip
  unsupported=urls.any?{|u|u.match?(/(?:[?&]location=unsupported(?:[&#]|$)|\/unsupported(?:[\/?#]|$))/i)}
  final=effective.to_s.downcase
  login=final.match?(/\Ahttps:\/\/accounts\.google\.com(?:[\/?#]|$)/)
  app=final.match?(/\Ahttps:\/\/(?:notebooklm\.google\.com|notebook\.google\.com)(?:[\/?#]|$)/)
  workspace=final.match?(/\Ahttps:\/\/(?:notebooklm\.google\.com|notebook\.google\.com)\/notebook\/[a-z0-9_-]{6,}(?:[\/?#]|$)/)
  landing=final.match?(/\Ahttps:\/\/(?:notebooklm\.google|notebook\.google)(?:[\/?#]|$)/)
  state=if unsupported
    'UNSUPPORTED_REDIRECT_OBSERVED'
  elsif rc==28
    'HTTP_INCOMPLETE_TIMEOUT'
  elsif rc!=0
    'REQUEST_INCOMPLETE'
  elsif login
    'LOGIN_REQUIRED_UNKNOWN'
  elsif code.to_i==403 || code.to_i==451
    'ACCESS_DENIED_UNKNOWN_CAUSE'
  elsif code.to_i==429
    'RATE_LIMITED'
  elsif app && workspace && code.to_i==200
    'WORKSPACE_URL_CANDIDATE_NOT_VERIFIED'
  elsif app && code.to_i==200
    'APP_ENTRY_CANDIDATE_NOT_VERIFIED'
  elsif landing
    'LANDING_ONLY_UNKNOWN'
  else
    'UNVERIFIED_REDIRECT_OR_HTTP'
  end
  puts "#{state} #{hops}"
rescue StandardError
  puts 'PARSER_FAILED 0'
end
RUBY_NOTEBOOK
)
      state=${decision%% *}
      redirects=${decision#* }
      echo "$tag NOTEBOOKLM=$state HTTP=$code CURL_RC=$rc TTFB_SEC=$ttfb TIME_SEC=$total BYTES=$bytes REDIRECTS=$redirects BUSINESS=UNKNOWN"
    else
      result=$(curl -4 --noproxy '' -sS --proxy http://127.0.0.1:17881 --connect-timeout 4 --max-time 9 -o /dev/null -w '%{http_code} %{time_starttransfer} %{time_total} %{size_download}' "$url" 2>"$D/$svc.curl.log")
      rc=$?
      code=${result%% *}
      rest=${result#* }
      ttfb=${rest%% *}
      rest=${rest#* }
      total=${rest%% *}
      bytes=${rest#* }
      outcome=$(classify_http "$rc" "$code")
      echo "$tag $svc=$outcome HTTP=$code CURL_RC=$rc TTFB_SEC=$ttfb TIME_SEC=$total BYTES=$bytes"
    fi
  done
  echo "$tag QUALIFICATION=NETWORK_HINT_ONLY BUSINESS=UNKNOWN"
  exit 0
)
end=$((START+COUNT-1))
echo "BATCH=START FROM=$START TO=$end TOTAL_SOURCE=58"
n="$START"
while [ "$n" -le "$end" ]; do
  if ! run_one "$n"; then echo "BATCH=STOPPED AT=$n";exit 1;fi
  n=$((n+1))
done
echo "BATCH=COMPLETE FROM=$START TO=$end BUSINESS_VERIFIED=NO"
