#!/bin/sh
# One final targeted, read-only map after the previous installer HOLD.
# Prints only fixed control-flow vocabulary and allowlisted variable names,
# never original source text, credentials, URLs, paths or their values.
set -eu
ROOT=/mnt/sata1-4/clash-home
WATCH="$ROOT/watch-clash-li.sh"
[ -f "$WATCH" ] && [ ! -L "$WATCH" ] || { echo 'HOLD=WATCH_FILE_MISSING'; exit 1; }
command -v ruby >/dev/null 2>&1 || { echo 'HOLD=RUBY_MISSING'; exit 1; }
ruby - "$WATCH" <<'RUBY'
path=ARGV[0]
lines=File.binread(path).force_encoding('UTF-8').scrub.lines
unless File.size(path)==3310 && lines.size==146
  puts 'HOLD=SOURCE_IDENTITY_DIFFERENT'
  exit 1
end
guard={
  'L15_LOCK_ASSIGN'=>/^\s*LOCK=/,
  'L23_IF'=>/^\s*if\b/,
  'L32_TRAP'=>/\btrap\b/,
  'L105_IF'=>/^\s*if\b/,
  'L121_RC'=>/\bRC\b/
}
puts 'REPORT=TARGETED_WATCH_BLOCK_READ_ONLY'
guard.each do |key,re|
  n=key[/L(\d+)/,1].to_i
  puts "#{key}=#{re.match?(lines[n-1]) ? 'YES' : 'NO'}"
end
names=%w[NEED_REFRESH OC_CHANGED INI_CHANGED RC BASE LOG OC_FILE INI_URL OC_STATE INI_STATE TMP LOCK GITHUB_FAIL]
puts '=== ORIGINAL_REFRESH_BLOCK_SHAPE_L90_TO_L146 ==='
(90..146).each do |n|
  line=lines[n-1].strip
  next if line.empty? || line.start_with?('#')
  kind=line[/\A(?:if|elif|else|fi|for|while|do|done|case|esac|then|return|exit|trap)\b/]
  set=line[/\A(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=/,1]
  set=names.include?(set) ? set : nil
  used=names.select{|word| /(?<![A-Za-z0-9_])#{Regexp.escape(word)}(?![A-Za-z0-9_])/.match?(line)}
  test=line.scan(/-(?:eq|ne|gt|ge|lt|le)\b/).uniq
  action=[]
  action << 'RUN_REFRESH' if /refresh-current\.sh/.match?(line)
  action << 'CHECK_NEED_REFRESH' if /\bNEED_REFRESH\b/.match?(line) && (/\bif\b|-(?:eq|ne)\b/.match?(line))
  action << 'WRITE_STATE' if /\bmv\b|\bcp\b/.match?(line)
  action << 'SLEEP' if /\bsleep\b/.match?(line)
  action << 'LOG' if /\bLOG\b/.match?(line) && /\becho\b|\bprintf\b/.match?(line)
  action << 'EXIT_STATUS' if /\bexit\b/.match?(line)
  next if !kind && !set && used.empty? && test.empty? && action.empty?
  fields=["L#{n}"]
  fields << "FLOW=#{kind.upcase}" if kind
  fields << "SET=#{set}" if set
  fields << "REFS=#{used.join(',')}" unless used.empty?
  fields << "TEST=#{test.join(',')}" unless test.empty?
  fields << "OP=#{action.join(',')}" unless action.empty?
  puts fields.join(' ')
end
puts 'RESULT=READ_ONLY_NO_FILES_CHANGED_NO_SECRETS_PRINTED'
RUBY
