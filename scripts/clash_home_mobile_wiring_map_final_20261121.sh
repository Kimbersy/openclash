#!/bin/sh
# Read-only one-screen-friendly wiring map of the existing clash-home scripts.
# No raw code, file paths other than fixed labels, subscriptions, URLs, credentials,
# env values, node names, config contents, or log text are printed.
set -eu
ROOT=/mnt/sata1-4/clash-home
[ -d "$ROOT" ] && [ ! -L "$ROOT" ] || { echo 'HOLD=CLASH_HOME_ROOT_MISSING'; exit 1; }
command -v ruby >/dev/null 2>&1 || { echo 'HOLD=RUBY_MISSING'; exit 1; }
ruby - "$ROOT" <<'RUBY'
root=ARGV.fetch(0)
targets = {
 'watch-clash-li.sh' => [[1,56],[99,146]],
 'refresh-current.sh' => [[1,11]],
 'refresh.py' => [[1,21],[65,94]]
}
op_regex = {
 'HASH' => /sha256sum|shasum|hashlib|digest/i,
 'WATCH' => /watch|changed|trigger|mtime|stat\b|checksum|fingerprint/i,
 'REFRESH' => /refresh/i,
 'HTTP' => /curl|wget|urllib|requests\.|urlopen/i,
 'ATOMIC' => /os\.replace|rename\(|replace\(|\bmv\b/i,
 'LOCK' => /flock|lock|mkdir/i,
 'TEMP' => /mktemp|tempfile|\.tmp|temporary/i,
 'SNI' => /\bsni\b|anytls/i,
 'CACHE' => /cache|merged/i,
 'CONVERTER' => /subconverter|25500|nostalgic_pasteur/i,
 'SLEEP' => /\bsleep\b/i,
 'ERROR' => /\bexcept\b|\btrap\b|exit\s+[1-9]|\braise\b/i
}
known_files = {
 'Clash-Li.ini'=>'TEMPLATE',
 'merged.yaml'=>'MOBILE_CACHE',
 'refresh-current.sh'=>'REFRESH_WRAPPER',
 'refresh.py'=>'REFRESH_GENERATOR',
 '云.yaml'=>'ROUTER_YAML'
}
puts 'REPORT=CLASH_HOME_EXISTING_WIRING_MAP_READ_ONLY'
targets.each do |filename,ranges|
  path=File.join(root,filename)
  unless File.file?(path) && !File.symlink?(path) && File.size(path)<20_000
    puts "FILE=#{filename} STATUS=HOLD_MISSING_OR_UNEXPECTED"
    next
  end
  raw=File.binread(path).force_encoding('UTF-8').scrub.lines
  puts "FILE=#{filename} LINES=#{raw.length} BYTES=#{File.size(path)}"
  shown=0
  cap=(filename=='watch-clash-li.sh' ? 54 : 18)
  raw.each_with_index do |line,i|
    n=i+1
    next unless ranges.any?{|lo,hi| n>=lo && n<=hi}
    stripped=line.strip
    next if stripped.empty? || stripped.start_with?('#')
    op=op_regex.select{|k,re| re.match?(stripped)}.keys
    flow=stripped[/\A(if|elif|else|fi|for|while|do|done|case|esac|try|except|finally|return|trap|exit|def)\b/,1]
    assign=stripped[/\A(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=/,1]
    vars=stripped.scan(/\$\{?([A-Za-z_][A-Za-z0-9_]*)/).flatten.uniq
    vars=vars.first(5)
    files=known_files.select{|k,v|stripped.include?(k)}.values
    # No source text, literal values, endpoints, or arbitrary identifiers.
    important=(!op.empty? || !files.empty? || assign || (flow && !vars.empty?))
    next unless important
    if shown < cap
      fields=["L#{n}"]
      fields << "FLOW=#{flow.upcase}" if flow
      fields << "SET=#{assign}" if assign
      fields << "USE=#{vars.join(',')}" unless vars.empty?
      fields << "OPS=#{op.join(',')}" unless op.empty?
      fields << "ROLE=#{files.join(',')}" unless files.empty?
      puts fields.join(' ')
      shown+=1
    end
  end
  puts "SUMMARY_SHOWN=#{shown} CAP=#{cap}"
end
puts 'WIRING_MAP=NO_SECRETS_NO_EXECUTION_NO_CHANGES'
RUBY
