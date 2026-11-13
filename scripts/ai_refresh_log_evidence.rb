#!/usr/bin/env ruby
# frozen_string_literal: true
# Read-only, anonymous source-update log evidence. NOT a success/reload gate.
# No log excerpts, paths, names, addresses, proxy details or credentials printed.
require 'time'

module AiRefreshLogEvidence
  module_function

  TIME_RE = /\A(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) \[(Info|Error|Warning)\] (.+)\z/
  MAX_LOG_BYTES = 2_000_000
  MAX_AGE = 48 * 3600

  def event_kind(message, alias_name, level)
    return nil unless alias_name.is_a?(String) && !alias_name.empty?
    prefix = "Config File【#{alias_name}】"
    if message.start_with?(prefix)
      suffix = message.delete_prefix(prefix)
      return 'SUCCESS_REPORTED' if level == 'Info' && suffix == 'Update Successful!'
      return 'NO_CHANGE_REPORTED' if level == 'Info' && suffix == 'No Change, Do Nothing!'
      return 'ERROR_REPORTED' if level == 'Error' &&
        (suffix.include?('Failed') || suffix.include?('Error'))
    end
    if level == 'Error' && message.start_with?("【#{alias_name}】Update Error")
      return 'ERROR_REPORTED'
    end
    nil
  end

  def classify(contents, alias_name, now: Time.now, max_age: MAX_AGE)
    return {'status'=>'UNAVAILABLE', 'age'=>'UNAVAILABLE'} unless contents.is_a?(String) && contents.bytesize <= MAX_LOG_BYTES
    return {'status'=>'ALIAS_UNAVAILABLE', 'age'=>'UNAVAILABLE'} unless alias_name.is_a?(String) && !alias_name.empty?
    events = []
    contents.each_line do |line|
      m = TIME_RE.match(line.chomp)
      next unless m
      kind = event_kind(m[3], alias_name, m[2])
      next unless kind
      begin
        ts = Time.strptime(m[1], '%Y-%m-%d %H:%M:%S')
      rescue ArgumentError
        next
      end
      events << [ts, kind]
    end
    return {'status'=>'NO_MATCH', 'age'=>'UNAVAILABLE'} if events.empty?
    latest = events.map(&:first).max
    age_secs = now - latest
    return {'status'=>'FUTURE_OR_BAD_CLOCK', 'age'=>'FUTURE'} if age_secs < -120
    return {'status'=>'STALE', 'age'=>'OLDER'} if age_secs > max_age
    kinds = events.select { |ts, _| ts == latest }.map(&:last).uniq
    state = if kinds.include?('ERROR_REPORTED')
      'ERROR_REPORTED'
    elsif kinds.size > 1
      'AMBIGUOUS'
    else
      kinds.first
    end
    band = age_secs < 3600 ? 'LT1H' : age_secs < 86400 ? 'LT24H' : 'LT48H'
    {'status'=>state, 'age'=>band}
  end

  def safe_alias
    selected = IO.popen(['uci','-q','get','openclash.config.config_path'], err: File::NULL) { |io| io.read.to_s.strip }
    return nil if selected.empty? || selected.include?("\0")
    basename = File.basename(selected)
    return nil unless basename.match?(/\A[^\r\n\/\\]+\.ya?ml\z/i)
    basename.sub(/\.ya?ml\z/i, '')
  rescue StandardError
    nil
  end

  def read_existing_log
    path = '/tmp/openclash.log'
    return nil unless File.file?(path) && File.size(path).between?(1, MAX_LOG_BYTES)
    return nil if File.symlink?(path)
    File.binread(path)
  rescue StandardError
    nil
  end

  def run
    result = classify(read_existing_log, safe_alias)
    puts "SUBSCRIPTION_LOG_EVIDENCE=#{result.fetch('status')} AGE=#{result.fetch('age')}"
    puts 'REMOTE_UPDATE_SUCCESS=NOT_PROVEN_BY_LOG'
    puts 'Mihomo_RUNTIME_RELOAD=NOT_VERIFIED'
    puts 'AI_CONTROL_ACTION=NONE'
    0
  rescue StandardError
    puts 'SUBSCRIPTION_LOG_EVIDENCE=UNAVAILABLE'
    puts 'AI_CONTROL_ACTION=NONE'
    2
  end
end

exit AiRefreshLogEvidence.run if $PROGRAM_NAME == __FILE__
