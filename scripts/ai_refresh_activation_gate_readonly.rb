#!/usr/bin/env ruby
# frozen_string_literal: true
# Strict, read-only OpenClash update -> restarted-core evidence gate.
# Never prints node names, alias, IP addresses, URLs, passwords or logfile lines.
# A successful log entry and disk equality are not sufficient by themselves.
require 'psych'
require_relative 'ai_proc_clock_readonly'

module AiRefreshActivationGate
  module_function

  MAX_AGE = 2 * 86_400
  # Parse local OpenClash log timestamps using Ruby core only (OpenWrt ruby-core
  # may not ship the optional 'time' stdlib). Reject invalid/normalized dates.
  def parse_log_timestamp(raw)
    parts = raw.split(/[- :]/).map { |v| Integer(v, 10) }
    return nil unless parts.length == 6
    year, month, day, hour, minute, second = parts
    return nil unless year.between?(2000, 9999) && month.between?(1, 12) &&
                      day.between?(1, 31) && hour.between?(0, 23) &&
                      minute.between?(0, 59) && second.between?(0, 59)
    value = Time.local(year, month, day, hour, minute, second)
    return nil unless [value.year, value.month, value.day, value.hour, value.min, value.sec] == parts
    value
  rescue ArgumentError, RangeError
    nil
  end

  def events(log, alias_name)
    return [] unless log.is_a?(String) && alias_name.is_a?(String) && alias_name.bytesize.between?(1, 256)
    escaped = Regexp.escape(alias_name)
    pattern = /\A(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) \[(?:Info|Error|Tip|Warning)\] (.*?)\z/
    log.lines.filter_map do |line|
      match = pattern.match(line.chomp)
      next unless match
      message = match[2]
      kind = case message
             when /\AConfig File(?:【#{escaped}】|〖#{escaped}〗)Update Successful!\z/
               'UPDATED'
             when /\AConfig File(?:【#{escaped}】|〖#{escaped}〗)No Change, Do Nothing!\z/
               'NO_CHANGE'
             when /\A(?:Config File(?:【#{escaped}】|〖#{escaped}〗)Subscribed Failed.*|(?:【#{escaped}】|〖#{escaped}〗)Update Error.*)\z/
               'FAILED'
             end
      next unless kind
      parsed_time = parse_log_timestamp(match[1])
      parsed_time && [parsed_time, kind]
    end
  end

  def decision(log:, alias_name:, now:, source_mtime:, core_start_time:,
               source_disk_matches_runtime:, single_source:, runtime_core_count:)
    entries = events(log, alias_name)
    entry = entries.last
    return 'NO_LOG_EVENT' unless entry
    time, status = entry
    return 'LOG_STALE_OR_FUTURE' unless (now - time).between?(0, MAX_AGE)
    return 'LATEST_UPDATE_FAILED' if status == 'FAILED'
    return 'NO_CONTENT_CHANGE' if status == 'NO_CHANGE'
    return 'SOURCE_NOT_UNIQUE' unless single_source
    return 'RUNTIME_AMBIGUOUS' unless runtime_core_count == 1
    return 'DISK_DEFINITIONS_DIFFER' unless source_disk_matches_runtime == true
    return 'UNKNOWN_FILE_TIME' unless source_mtime.is_a?(Time)
    return 'SOURCE_CHANGED_AFTER_LOG' if source_mtime > time + 3
    return 'SOURCE_MTIME_TOO_OLD' if source_mtime < time - 180
    return 'CORE_START_UNVERIFIED' unless core_start_time.is_a?(Time)
    return 'CORE_PREDATES_UPDATE' if core_start_time < time - 3 || core_start_time < source_mtime - 3
    return 'CLOCK_INCONSISTENT' if core_start_time > now + 3
    'COLD_START_AFTER_UPDATE_CANDIDATE'
  rescue StandardError
    'EVIDENCE_UNAVAILABLE'
  end

  def selected_source
    selected = IO.popen(['uci','-q','get','openclash.config.config_path'], err: File::NULL) { |io| io.read.to_s.strip }
    return nil unless selected.is_a?(String) && !selected.empty?
    root = '/etc/openclash/config/'
    path = File.expand_path(selected.start_with?('/') ? selected : File.join(root,selected))
    return nil unless path.start_with?(root) && File.file?(path) && File.size(path).between?(1,20_000_000)
    return nil unless File.realpath(path).start_with?(root)
    path
  rescue StandardError
    nil
  end

  def one_source_alias(selected)
    uci = IO.popen(['uci','-q','show','openclash'], err: File::NULL) { |io| io.read.to_s }
    ids = uci.scan(/^openclash\.([^.=]+)=config_subscribe\s*$/).flatten.uniq
    return nil unless ids.length == 1
    key = "openclash.#{ids.first}"
    enabled = IO.popen(['uci','-q','get',"#{key}.enabled"], err: File::NULL) { |io| io.read.to_s.strip }
    name = IO.popen(['uci','-q','get',"#{key}.name"], err: File::NULL) { |io| io.read.to_s.strip }
    name = 'config' if name.empty?
    return nil unless enabled == '1' && name.match?(/\A[^\/\x00-\x1f]{1,128}\z/)
    expected = File.expand_path("/etc/openclash/config/#{name}.yaml")
    selected == expected ? name : nil
  rescue StandardError
    nil
  end

  def core_records
    records = []
    Dir['/proc/[0-9]*/cmdline'].each do |cp|
      begin
        pid = cp.split('/')[2].to_i
        exe = File.readlink("/proc/#{pid}/exe")
        next unless exe.start_with?('/etc/openclash/core/')
        argv = File.binread(cp).split("\0")
        next if argv.any? { |x| x.include?('/tmp/openclash-ai-') || x.include?('/tmp/openclash-probe-') || x.include?('/tmp/oc-ai-') }
        cwd = File.readlink("/proc/#{pid}/cwd")
        opts = ->(key) { idx = argv.index(key); idx ? argv[idx + 1] : argv.find { |v| v.start_with?("#{key}=") }&.split('=',2)&.last }
        dir = File.expand_path(opts.call('-d') || cwd, cwd)
        path = File.expand_path(opts.call('-f') || 'config.yaml', dir)
        next unless File.file?(path) && File.size(path).between?(1,20_000_000)
        records << [pid, path]
      rescue StandardError
        next
      end
    end
    records
  end

  def process_start(pid)
    AiProcClockReadOnly.core_start_time(pid)
  end

  def definitions_match?(source, runtime)
    a=Psych.safe_load(File.binread(source), aliases:false)
    b=Psych.safe_load(File.binread(runtime), aliases:false)
    a.is_a?(Hash) && b.is_a?(Hash) &&
      a['proxies'].is_a?(Array) && b['proxies'].is_a?(Array) &&
      a['proxies'] == b['proxies']
  end

  def run
    source = selected_source
    alias_name = source && one_source_alias(source)
    puts "SOURCE_ALIAS_LINK=#{alias_name ? 'MATCH' : 'UNVERIFIED'}"
    cores = core_records
    puts "RUNTIME_CORES=#{cores.length == 1 ? 'ONE' : 'NOT_EXACTLY_ONE'}"
    core_start = cores.length == 1 ? process_start(cores.first[0]) : nil
    disk_match = !!(source && cores.length == 1 && definitions_match?(source,cores.first[1]))
    puts "SOURCE_RUNTIME_DISK_DEFINITIONS=#{disk_match ? 'MATCH' : 'UNVERIFIED_OR_DIFFER'}"
    logfile = '/tmp/openclash.log'
    log = File.file?(logfile) && File.size(logfile).between?(1,1_000_000) ?
       File.binread(logfile).force_encoding('UTF-8').scrub : ''
    proof = decision(log:log, alias_name:alias_name, now:Time.now,
                     source_mtime:source && File.mtime(source),
                     core_start_time:core_start, source_disk_matches_runtime:disk_match,
                     single_source:!!alias_name, runtime_core_count:cores.length)
    puts "POST_UPDATE_ACTIVATION_EVIDENCE=#{proof}"
    puts 'MIHOMO_RUNTIME_API_CONTENT=NOT_QUERIED'
    puts 'REMOTE_DOWNLOAD_EXIT_STATUS=NOT_CAPTURED'
    puts 'FULL_AI_POOL_UPDATE_GATE=BLOCKED_PENDING_RUNTIME_API_AND_SUCCESS_RECEIPT'
    puts 'READ_ONLY=YES PRODUCTION_WRITES=NONE'
    0
  rescue StandardError
    puts 'ACTIVATION_PROBE=UNAVAILABLE_NO_PRIVATE_OUTPUT'
    2
  end
end
exit AiRefreshActivationGate.run if __FILE__ == $PROGRAM_NAME
