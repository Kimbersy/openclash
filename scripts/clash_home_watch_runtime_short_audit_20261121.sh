#!/bin/sh
# One-screen read-only verification of the EXISTING clash-home watcher scheduling
# and its pre-refresh failure/lock state. Never calls watcher or converter.
set -eu
ROOT='/mnt/sata1-4/clash-home'
WATCH="$ROOT/watch-clash-li.sh"
[ -f "$WATCH" ] && [ ! -L "$WATCH" ] || { echo 'HOLD=WATCH_NOT_FOUND'; exit 1; }
command -v ruby >/dev/null 2>&1 || { echo 'HOLD=RUBY_NOT_AVAILABLE'; exit 1; }
ruby - "$ROOT" <<'RUBY'
root=ARGV.fetch(0)
watch=File.join(root,'watch-clash-li.sh')
s=File.binread(watch)
unless s.include?('MOBILE_CONVERTER_IMAGE_WATCH_V1') &&
       s.include?('CONVERTER_TRIGGER=1') &&
       s.include?('MOBILE_CONVERTER_AUTO_REFRESH')
  puts 'HOLD=EXPECTED_WATCH_PATCH_NOT_FOUND';exit 1
end
puts 'WATCH_PATCH=INSTALLED'
ack=File.join(root,'.last_mobile_converter_image_id')
retry_file=File.join(root,'.last_mobile_converter_retry')
puts "IMAGE_ACK_FILE=#{File.file?(ack) ? 'PRESENT' : 'ABSENT'}"
puts "IMAGE_RETRY_FILE=#{File.file?(retry_file) ? 'PRESENT' : 'ABSENT'}"
cron_text=''
cron_sources=['/etc/crontabs/root','/var/spool/cron/crontabs/root']
cron_sources.each do |path|
  begin
    cron_text=File.binread(path) if File.file?(path)
    break unless cron_text.empty?
  rescue StandardError
  end
end
if cron_text.empty?
  puts 'CRON_SOURCE=UNREADABLE_OR_EMPTY'
else
  active=cron_text.lines.map(&:strip).reject{|l| l.empty?||l.start_with?('#')}
  watch_entries=active.select{|l| l.include?('watch-clash-li.sh')}
  refresh_entries=active.select{|l| l.include?('refresh-current.sh')}
  puts "CRON_WATCH_ENTRIES=#{watch_entries.size}"
  puts "CRON_REFRESH_ENTRIES=#{refresh_entries.size}"
  puts "CRON_WATCH_5MIN=#{watch_entries.any?{|l| l.match?(/\A\*\/5\s+\*\s+\*\s+\*\s+\*/)} ? 'YES' : 'NO_OR_DIFFERENT_SCHEDULE'}"
  puts "CRON_REFRESH_0430=#{refresh_entries.any?{|l| l.match?(/\A30\s+4\s+\*\s+\*\s+\*/)} ? 'YES' : 'NO_OR_DIFFERENT_SCHEDULE'}"
end

# The existing watcher defines LOG and LOCK. Extract ONLY simple local paths
# under ROOT, or a fixed /tmp lock; never print resolved path or source line.
lines=s.lines
def local_path_from_assignment(line,root,key)
  str=line.strip
  m=str.match(/\A#{Regexp.escape(key)}=(?:"([^"]+)"|'([^']+)'|([^\s#]+))/)
  return nil unless m
  value=m.captures.compact.first
  base_ref='$'+'{BASE}/'
  if value.start_with?('$BASE/')
    resolved=File.expand_path(value.sub('$BASE/',root+'/'))
  elsif value.start_with?(base_ref)
    resolved=File.expand_path(value.sub(base_ref,root+'/'))
  elsif value.start_with?('/tmp/') && key=='LOCK'
    resolved=File.expand_path(value)
  else
    return nil
  end
  return nil if resolved.include?("\n")||resolved.include?("\r")
  return nil unless resolved.start_with?(root+'/') || (key=='LOCK'&&resolved.start_with?('/tmp/'))
  resolved
end
log=local_path_from_assignment(lines[12]||'',root,'LOG')
lock=local_path_from_assignment(lines[14]||'',root,'LOCK')
if lock
  puts "WATCH_LOCK_PATH_STATUS=#{File.directory?(lock) ? 'DIRECTORY_PRESENT' : (File.exist?(lock) ? 'OTHER_EXISTS' : 'ABSENT')}"
else
  puts 'WATCH_LOCK_PATH_STATUS=UNKNOWN_FORMAT'
end
if log && File.file?(log) && !File.symlink?(log)
  age=Time.now.to_i-File.mtime(log).to_i
  puts "WATCH_LOG_AGE_SECONDS=#{age}"
  # Never print source log or user URLs. Only event classes and their counts
  # in the final 200 lines, to avoid unrelated historical entries.
  recent=File.binread(log).lines.last(200).join
  %w[MOBILE_CONVERTER_AUTO_REFRESH=PASS_A01_SNI MOBILE_CONVERTER_AUTO_REFRESH=HOLD_ORIGINAL_CACHE_RESTORED MOBILE_CONVERTER_AUTO_REFRESH=HOLD_MANUAL_CACHE_RESTORE_REQUIRED].each do |tag|
    puts "WATCH_LOG_#{tag.sub('MOBILE_CONVERTER_AUTO_REFRESH=','')}=#{recent.scan(tag).size}"
  end
  puts "WATCH_LOG_REFRESH_MENTION=#{recent.match?(/refresh-current\.sh|refresh failed|刷新/i) ? 'YES' : 'NO'}"
  puts "WATCH_LOG_GITHUB_MENTION=#{recent.match?(/github|Clash-Li\.ini/i) ? 'YES' : 'NO'}"
else
  puts 'WATCH_LOG_STATUS=MISSING_OR_UNRECOGNIZED'
end

# Classify the precisely known pre-trigger early-exit branches,
# without printing strings, URLs, arguments or values.
before=lines[0...104]
puts "EARLY_EXIT_LINES_BEFORE_TRIGGER=#{before.each_with_index.select{|line,i| line.match?(/\bexit\s+[0-9]+\b/)}.map{|line,i|i+1}.join(',')}"
puts 'READ_ONLY=YES_NO_REFRESH_NO_CHANGES'
RUBY
