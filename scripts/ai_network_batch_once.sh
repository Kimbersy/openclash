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
  D="/tmp/openclash-ai-batch-$idx-$(date +%s)-$"
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
  if ! ruby -rpsych - "$idx" "$D" <<'RUBY_PREP'
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
  sample=ps[idx-1]
  raise unless sample && !sample['dialer-proxy'] && !%w[direct reject reject-drop pass compatible].include?(sample['type'].downcase)
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
  then exit 1; fi
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
  if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -n "$ipcc" ] && [ "$ipcc" = "$cfcc" ] && [ "$ipv4" = "$cfip" ]; then
    echo "$tag EXIT_COUNTRY=$ipcc GEO_SOURCES=AGREE IPV4_MATCH=YES"
  else
    echo "$tag EXIT_COUNTRY=UNVERIFIED GEO_SOURCES=INCOMPLETE_OR_CONFLICT"
  fi

  for svc in CHATGPT GEMINI NOTEBOOKLM; do
    case "$svc" in
      CHATGPT) url=https://chatgpt.com/ ;;
      GEMINI) url=https://gemini.google.com/ ;;
      NOTEBOOKLM) url=https://notebooklm.google.com/ ;;
    esac
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
