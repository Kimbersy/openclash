#!/bin/sh
# Read-only metadata and cache comparison for existing clash-home 18080 service.
# All proxy names, credentials, URLs, file contents and log text stay on iStoreOS.
set -eu
umask 077
ROOT='/mnt/sata1-4/clash-home'
for cmd in docker curl ruby mkdir rm rmdir; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "HOLD_MISSING_COMMAND=$cmd"; exit 1; }
done
[ -d "$ROOT" ] && [ ! -L "$ROOT" ] || {
  echo 'HOLD_HISTORIC_CLASH_HOME_DIRECTORY_MISSING'
  exit 1
}
docker inspect -f 'CLASH_HOME_RUNNING={{.State.Running}} CLASH_HOME_MOUNTS={{len .Mounts}}' clash-home 2>/dev/null || {
  echo 'HOLD_CLASH_HOME_NOT_FOUND'
  exit 1
}
echo 'AUDIT_MODE=READ_ONLY_NO_REFRESH_NO_CACHE_DELETION'
echo "HOST_TIME=$(date '+%Y-%m-%d_%H:%M:%S_%z')"

WORK="/tmp/clash-home-cache-check-$$"
mkdir "$WORK" || { echo 'HOLD_CANNOT_CREATE_TEMP'; exit 1; }
trap 'rm -f "$WORK/mobile.yaml"; rmdir "$WORK" 2>/dev/null || true' EXIT
trap 'exit 1' HUP INT TERM
if curl --noproxy '*' -fsS --connect-timeout 3 --max-time 30 \
  http://127.0.0.1:18080/ -o "$WORK/mobile.yaml"; then
  echo 'MOBILE_HTTP=PASS'
else
  echo 'HOLD_MOBILE_HTTP_FETCH_FAILED'
  exit 1
fi

ruby - "$ROOT" "$WORK/mobile.yaml" <<'RUBY'
begin
  require 'psych'
  root, served_path = ARGV
  served = File.binread(served_path)
  yaml = Psych.safe_load(served, permitted_classes: [], permitted_symbols: [], aliases: true)
  unless yaml.is_a?(Hash) && yaml['proxies'].is_a?(Array)
    puts 'HOLD_MOBILE_YAML_NO_PROXIES'
    exit 1
  end
rescue StandardError
  puts 'HOLD_MOBILE_YAML_UNREADABLE'
  exit 1
end

a01rx = /(?:^|[^A-Za-z0-9])A[\s_-]*0?1(?=[^A-Za-z0-9]|$)/i
counts = ->(config) do
  nodes = config.is_a?(Hash) ? config['proxies'] : nil
  return nil unless nodes.is_a?(Array)
  tls = nodes.select { |p| p.is_a?(Hash) && p['type'].to_s.downcase == 'anytls' }
  a01 = tls.select { |p| p['name'].is_a?(String) && a01rx.match?(p['name']) }
  [nodes.length, tls.length, tls.count { |p| p['sni'].to_s.strip.empty? },
    a01.length, a01.count { |p| p['sni'].to_s.strip.empty? }]
end
printcounts = ->(prefix, arr) do
  puts "#{prefix}_PROXIES=#{arr[0]} #{prefix}_ANYTLS=#{arr[1]} #{prefix}_ANYTLS_MISSING_SNI=#{arr[2]} #{prefix}_A01=#{arr[3]} #{prefix}_A01_MISSING_SNI=#{arr[4]}"
end
printcounts.call('SERVED_18080', counts.call(yaml))

['refresh-current.sh', 'watch-clash-li.sh', 'merge.py', 'refresh.log'].each do |basename|
  path = File.join(root, basename)
  label = basename.upcase.gsub(/[^A-Z0-9]/,'_')
  if File.file?(path) && !File.symlink?(path)
    st = File.stat(path)
    puts "#{label}_PRESENT=YES MTIME=#{st.mtime.strftime('%Y-%m-%d_%H:%M:%S_%z')} BYTES=#{st.size}"
    if basename.end_with?('.sh', '.py') && st.size <= 200_000
      content = File.binread(path)
      ['25500','18080','cache','current','rename','replace','mv ','curl','subconverter','yaml'].each do |term|
        puts "#{label}_MENTIONS_#{term.gsub(/[^A-Za-z0-9]/, '_').upcase}=#{content.include?(term) ? 'YES' : 'NO'}"
      end
    end
  else
    puts "#{label}_PRESENT=NO"
  end
end

begin
  files = Dir.glob(File.join(root, '**', '*.{yaml,yml}'), File::FNM_CASEFOLD)
    .select { |p| File.file?(p) && !File.symlink?(p) && File.size(p) <= 8_000_000 }
    .sort_by { |p| -File.mtime(p).to_i }.first(32)
rescue StandardError
  puts 'HOLD_CACHE_FILE_ENUMERATION_FAILED'
  exit 1
end
puts "HOST_YAML_CANDIDATES_SCANNED=#{files.length}"
files.each_with_index do |path, i|
  next if File.size(path) == 0
  begin
    buf = File.binread(path)
    obj = Psych.safe_load(buf, permitted_classes: [], permitted_symbols: [], aliases: true)
    arr = counts.call(obj)
    next unless arr
    st = File.stat(path)
    rel = path.sub(root+'/', '')
    display = rel.match?(/\A(?:[A-Za-z0-9_-]+\/){0,3}(?:current|cache|cached|clash|mobile|merged|config|subscription)[A-Za-z0-9_.-]*\.(?:yaml|yml)\z/i) ? rel : '[filename-withheld]'
    prefix = "HOST_YAML_#{i+1}"
    puts "#{prefix}_FILE=#{display} MTIME=#{st.mtime.strftime('%Y-%m-%d_%H:%M:%S_%z')} BYTES=#{st.size} EXACT_18080_MATCH=#{buf == served ? 'YES' : 'NO'}"
    printcounts.call(prefix, arr)
  rescue StandardError
    puts "HOST_YAML_#{i+1}_PARSE=SKIPPED"
  end
end
puts 'CACHE_AUDIT_RESULT=READ_ONLY_METADATA_AND_SNI_COUNTS'
RUBY
