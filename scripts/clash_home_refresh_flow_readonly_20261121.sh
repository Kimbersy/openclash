#!/bin/sh
# Read-only, secret-safe structural map of the existing clash-home refresh code.
# Never outputs source code lines, env values, URL strings, node names or log content.
set -eu
ROOT='/mnt/sata1-4/clash-home'
[ -d "$ROOT" ] && [ ! -L "$ROOT" ] || { echo 'HOLD_ROOT_NOT_FOUND'; exit 1; }
command -v ruby >/dev/null 2>&1 || { echo 'HOLD_RUBY_MISSING'; exit 1; }
ruby - "$ROOT" <<'RUBY'
root = ARGV[0]
script_names = %w[
  refresh-current.sh watch-clash-li.sh merge.py
  app.py main.py server.py serve.py refresh.py cache.py
  entrypoint.sh start.sh cache_server.py
  Dockerfile compose.yaml docker-compose.yml docker-compose.yaml
]
tags = [
  ['CURL', /\bcurl\b/i],
  ['WGET', /\bwget\b/i],
  ['HTTP_LIBRARY', /requests|urllib|urlopen|urlretrieve|aiohttp|http\.client/i],
  ['DOCKER', /\bdocker\b/i],
  ['EXEC', /\bexec\b|subprocess|os\.system/i],
  ['PYTHON', /\bpython(?:3)?\b/i],
  ['PORT_25500', /\b25500\b/],
  ['PORT_18080', /\b18080\b/],
  ['PORT_8080', /\b8080\b/],
  ['CACHE', /\bcache\b|cache[\/_.-]/i],
  ['MERGED', /merged/i],
  ['SNI', /\bsni\b/i],
  ['SOURCE', /upstream|sub_url|sub_link|subscription|source_url|proxy_url/i],
  ['REFRESH', /refresh/i],
  ['WATCH', /watch/i],
  ['MERGE', /merge/i],
  ['YAML', /yaml|yml/i],
  ['READ', /\bread\b|\bopen\b|File\.read|read_text|read_bytes/i],
  ['WRITE', /\bwrite\b|copyfile|shutil\.copy|File\.write|write_text|write_bytes/i],
  ['ATOMIC', /os\.replace|os\.rename|rename\(|replace\(|\bmv\b|\binstall\b/i],
  ['TEMP', /tempfile|NamedTemporaryFile|mktemp|\.tmp\b|\/tmp\//i],
  ['LOCK', /flock|fcntl|lockfile|\.lock\b/i],
  ['BACKUP', /\bbackup\b|\.bak\b/i],
  ['ERROR_POLICY', /\bexcept\b|\btrap\b|set -e|raise\b|\bretry\b/i],
  ['ENV_LOOKUP', /getenv|environ|os\.environ/i],
  ['HTTP_SERVER', /Flask|app\.route|BaseHTTPRequestHandler|http\.server/i],
  ['SHELL_SOURCE', /(^|\s)\.\s+\/|(^|\s)source\s/i]
]

script_names.each do |name|
  p = File.join(root, name)
  unless File.file?(p) && !File.symlink?(p)
    puts "FILE=#{name} STATUS=ABSENT"
    next
  end
  if File.size(p)>200_000
    puts "FILE=#{name} STATUS=HOLD_TOO_LARGE"
    next
  end
  begin
    lines = File.binread(p).force_encoding('UTF-8').scrub.split("\n")
    puts "FILE=#{name} STATUS=PRESENT LINES=#{lines.size} BYTES=#{File.size(p)}"
    matched=0
    lines.each_with_index do |line,i|
      next if line.lstrip.start_with?('#')
      present=tags.filter_map { |label,re| label if re.match?(line) }
      next if present.empty?
      matched += 1
      puts "  L#{i+1}_OPS=#{present.join(',')}" if matched<=45
    end
    puts "  MATCHED_LINES=#{matched} TRUNCATED_AT_45=#{matched>45 ? 'YES' : 'NO'}"
  rescue StandardError
    puts "FILE=#{name} STATUS=HOLD_UNREADABLE"
  end
end
puts 'REFRESH_FLOW_AUDIT=READ_ONLY_NO_SOURCE_TEXT_NO_EXECUTION'
RUBY
