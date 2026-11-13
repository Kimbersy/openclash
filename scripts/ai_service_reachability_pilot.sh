#!/bin/sh
# One-time bounded HK1/TW1 AI landing-page transport probe on separate private Mihomo core.
# No login check, no parent group change, no API request to the production core.
set -u
umask 077
CORE=/etc/openclash/core/clash_meta
if [ ! -x "$CORE" ] || ! command -v ruby >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo 'PILOT=BLOCKED REASON=TOOLS'; exit 1
fi
run_one() (
  region="$1"
  D="/tmp/openclash-ai-reach-$region-$(date +%s)-$$"
  tag="$region"1
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
  raise unless %r{\A/tmp/openclash-ai-reach-(?:HK|TW)-\d+-\d+\z}.match?(d)
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
  if ! ruby -rpsych - "$region" "$D" <<'RUBY_PREP'
# encoding: UTF-8
begin
  r=ARGV.fetch(0);d=ARGV.fetch(1)
  raise unless %w[HK TW].include?(r)
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
  re=r=='HK' ? /香港|🇭🇰|\b(?:HK|HKG|Hong\s*Kong)\b/i : /台湾|臺灣|🇹🇼|\b(?:TW|TWN|Taiwan)\b/i
  sample=ps.find{|n|re.match?(n['name'])}
  raise unless sample && !sample['dialer-proxy'] && !%w[direct reject reject-drop pass compatible].include?(sample['type'].downcase)
  cfg={'allow-lan'=>false,'mode'=>'rule','log-level'=>'silent',
     'port'=>0,'socks-port'=>0,'mixed-port'=>0,'redir-port'=>0,'tproxy-port'=>0,
     'external-controller'=>'','tun'=>{'enable'=>false},
     'profile'=>{'store-selected'=>false,'store-fake-ip'=>false},'proxies'=>[sample],
     'listeners'=>[{'name'=>'audit-only','type'=>'http','listen'=>'127.0.0.1',
                    'port'=>17881,'proxy'=>sample['name']}],'rules'=>['MATCH,REJECT']}
  File.open(File.join(d,'isolated.yaml'),File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(Psych.dump(cfg))}
  raise unless File.binread(src)==raw
  puts "#{r}1 PREP=PASS CURRENT_NODES=#{ps.size} ISOLATED=YES"
rescue StandardError
  puts "#{ARGV[0]}1 PREP=BLOCKED"
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
    while [ "$n" -lt 48 ]; do [ -f "$stop" ] && exit 0; sleep 1; n=$((n+1)); done
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
  for svc in CHATGPT GEMINI NOTEBOOKLM; do
    case "$svc" in
      CHATGPT) url=https://chatgpt.com/ ;;
      GEMINI) url=https://gemini.google.com/ ;;
      NOTEBOOKLM) url=https://notebooklm.google.com/ ;;
    esac
    result=$(curl -4 --noproxy '' -sS --proxy http://127.0.0.1:17881 --connect-timeout 4 --max-time 9 -o /dev/null -w '%{http_code} %{time_total}' "$url" 2>"$D/$svc.curl.log")
    rc=$?
    code=$(printf '%s\n' "$result" | cut -d' ' -f1)
    elapsed=$(printf '%s\n' "$result" | cut -d' ' -f2)
    if [ "$rc" -ne 0 ]; then outcome=TRANSPORT_OR_TLS_FAILED
    else
      case "$code" in
        2??|3??) outcome=HTTP_RESPONSE ;;
        403|451) outcome=HTTP_DENIED ;;
        429) outcome=HTTP_RATE_LIMIT ;;
        5??) outcome=HTTP_SERVER_ERROR ;;
        *) outcome=HTTP_OTHER ;;
      esac
    fi
    echo "$tag $svc=$outcome HTTP=$code CURL_RC=$rc TIME_SEC=$elapsed"
  done
  echo "$tag QUALIFICATION=NETWORK_HINT_ONLY BUSINESS=UNKNOWN"
  exit 0
)
for region in HK TW; do
  if ! run_one "$region"; then echo "PILOT=STOPPED REGION=$region";exit 1;fi
done
echo 'PILOT=COMPLETE SAMPLES=HK1,TW1 BUSINESS_VERIFIED=NO'
