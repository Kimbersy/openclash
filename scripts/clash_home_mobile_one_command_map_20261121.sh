#!/bin/sh
# iStoreOS ClashMate cache: one-command, read-only, credential-safe source map.
# The report emits ONLY normalized operation names, safe identifiers,
# condition operators and line numbers, never source lines or their values.
set -eu
ROOT=/mnt/sata1-4/clash-home
[ -d "$ROOT" ] && [ ! -L "$ROOT" ] || { echo "HOLD=CLASH_HOME_ROOT_MISSING"; exit 1; }
command -v ruby >/dev/null 2>&1 || { echo "HOLD=RUBY_MISSING"; exit 1; }
ruby - "$ROOT" <<'RUBY'
root=ARGV.fetch(0)
names=['refresh-current.sh','watch-clash-li.sh','refresh.py','merge.py']
ops={
'REFRESH_ENTRY'=>/refresh-current\.sh|refresh\.py|refresh_current|run_refresh/i,
'WATCH_TRIGGER'=>/inotify|watch|mtime|last_?hash|sha256|changed|fingerprint|stat\W|hashlib/i,
'FILE_STABILITY'=>/stat -c|mtime|st_mtime|sleep|settle|age|st_size/i,
'LOCK'=>/flock|\.lock\b|mkdir\b.*lock|lockfile|os\.lockf/i,
'TIMING'=>/04:30|cron|datetime|time\.time|date \+|sleep/i,
'FETCH'=>/curl|wget|urllib|urlopen|requests\.|subprocess/i,
'SUBCONVERTER'=>/25500|subconverter|nostalgic_pasteur/i,
'SOURCE'=>/\bsource\b|SUB_URL|SOURCE_URL|subscription|base64|provider/i,
'CACHE'=>/merged\.yaml|cache\/|CACHE|os\.replace|rename\(|replace\(/i,
'VALIDATION'=>/yaml\.safe_load|safe_load|yaml\.load|proxies|proxy-groups|sni|AnyTLS/i,
'ERROR_GUARD'=>/except\b|trap\b|set -e|return 1|exit 1|raise\b/i,
'ENV'=>/os\.environ|os\.getenv|export\b|source\s+[^ ]|^\s*\.\s+/i
}
control = /(?:^|\s)(if|elif|else|fi|then|for|while|do|done|case|esac|try|except|finally|return|break|continue|def|function|with|trap)(?:\s|:|\(|$)/
summary={}
puts '=== CLASH_HOME_READ_ONLY_SOURCE_MAP ==='
names.each do |name|
  path=File.join(root,name)
  unless File.file?(path)&&!File.symlink?(path)
    puts "FILE=#{name} STATUS=MISSING"
    next
  end
  size=File.size(path)
  if size>20_000
    puts "FILE=#{name} STATUS=HOLD_TOO_LARGE"
    next
  end
  lines=File.binread(path).force_encoding('UTF-8').scrub.lines
  puts "FILE=#{name} STATUS=PRESENT LINES=#{lines.length} BYTES=#{size}"
  matches=0
  shown=0
  limit = name=='watch-clash-li.sh' ? 32 : (name=='refresh.py' ? 25 : 10)
  lines.each_with_index do |raw,i|
    s=raw.strip
    next if s.empty?||s.start_with?('#')
    # Fixed vocabulary only. No line text, strings, variable values, URLs,
    # environment values, paths, credentials or subscription names.
    found=ops.select{|key,re| re.match?(s)}.keys
    flow=s.match(/\A(?:def|if|elif|else|fi|for|while|do|done|case|esac|try|except|finally|return|trap|exit|function)\b/)
    if flow
      f=flow[0].upcase
      found.unshift("FLOW_#{f}")
    end
    function=s.match(/\Adef\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/)
    if function
      # No arbitrary identifiers in the stdout: only known operational names.
      name_token=function[1].downcase
      found << 'FUNC_REFRESH' if name_token.include?('refresh')
      found << 'FUNC_FETCH' if name_token.include?('fetch')
      found << 'FUNC_CACHE' if name_token.include?('cache')
      found << 'FUNC_MERGE' if name_token.include?('merge')
      found << 'FUNC_MAIN' if name_token=='main'
    end
    next if found.empty?
    matches+=1
    signal=found.any?{|t| ['REFRESH_ENTRY','WATCH_TRIGGER','FILE_STABILITY','LOCK','FETCH','SUBCONVERTER','SOURCE','CACHE','VALIDATION','ENV','ERROR_GUARD'].include?(t)}
    next unless signal
    if shown<limit
      puts "  L#{i+1}=#{found.uniq.join(',')}"
      shown+=1
    end
  end
  puts "  ANALYZED_LINES=#{matches} PRINTED=#{shown} CAP=#{limit}"
  summary[name]=matches
end
puts 'REPORT=SOURCE_MAP_ONLY_NO_VALUES_NO_CHANGES'
puts 'NEXT=RETURN_TERMINAL_OUTPUT_OR_SCREENSHOTS'
RUBY
