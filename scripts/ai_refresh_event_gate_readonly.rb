#!/usr/bin/env ruby
# frozen_string_literal: true
# Read-only cron + update-log hints. Never prints URLs, tokens, node/IP names,
# cron text or log lines. Log messages cannot prove Mihomo in-memory reload.
require 'time'
require_relative 'ai_refresh_schedule_readonly'

module AiRefreshEventGate
  module_function

  def cron_matches?(text, hour, week)
    return false unless text.is_a?(String) && hour.to_s.match?(/\A(?:[01]?\d|2[0-3])\z/)
    return false unless week == '*' || week.to_s.match?(/\A[0-6]\z/)
    pattern = /\A0\s+#{hour.to_i}\s+\*\s+\*\s+#{Regexp.escape(week)}\s+\/usr\/share\/openclash\/openclash\.sh(?:\s+#openclash-cron-task)?\s*\z/
    text.each_line.any? { |line| pattern.match?(line.strip) }
  end

  def event_kind(line, alias_name)
    return nil unless alias_name.is_a?(String) && alias_name.bytesize.between?(1, 180)
    escaped = Regexp.escape(alias_name)
    if /(?:配置文件|Config File)〖#{escaped}〗(?:\s*更新成功|\s*Update Successful)/i.match?(line)
      'REPLACED'
    elsif /(?:配置文件|Config File)〖#{escaped}〗(?:\s*没有更新|\s*No Change)/i.match?(line)
      'UNCHANGED'
    end
  end

  def event_line(line, alias_name, now = Time.now)
    m = /\A\s*(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\b/.match(line)
    return nil unless m
    kind = event_kind(line, alias_name)
    return nil unless kind
    stamp = Time.strptime("#{m[1]} #{m[2]}", '%Y-%m-%d %H:%M:%S')
    return nil if stamp > now + 120
    [stamp, kind]
  rescue ArgumentError, RangeError
    nil
  end

  def latest_event(log, alias_name, now = Time.now)
    return 'UNAVAILABLE' unless log.is_a?(String) && alias_name.is_a?(String) && !alias_name.empty?
    evidence = log.each_line.filter_map { |line| event_line(line, alias_name, now) }
    return 'NOT_FOUND' if evidence.empty?
    stamp, kind = evidence.max_by(&:first)
    return 'STALE' if now - stamp > 172_800
    kind == 'REPLACED' ? 'RECENT_REPLACED_LOG_HINT' : 'RECENT_UNCHANGED_LOG_HINT'
  end

  def safe_read(path, limit, tail = false)
    return nil unless File.file?(path) && !File.symlink?(path)
    size = File.size(path)
    return nil unless size.between?(1, 8_000_000)
    length = [size, limit].min
    offset = tail ? size - length : 0
    File.binread(path, length, offset).force_encoding('UTF-8').scrub('')
  rescue StandardError
    nil
  end

  def target_alias
    IO.popen(['uci', '-q', 'get', 'openclash.@config_subscribe[0].name'], err: File::NULL) { |io| io.read.to_s.strip }
  rescue StandardError
    ''
  end

  def disk_match
    src = AiRefreshSchedule.safe_source_file(AiRefreshSchedule.uci_read('config_path'))
    core = AiRefreshSchedule.live_core_config
    return 'UNAVAILABLE' unless src && core
    AiRefreshSchedule.disk_definitions_match?(src, core) ? 'MATCH' : 'DIFFER'
  rescue StandardError
    'UNAVAILABLE'
  end

  def gate(sched:, cron:, event:, disk:)
    return 'BLOCK_SCHEDULE' unless sched == 'ENABLED_DAILY' && cron == 'MATCH'
    return 'BLOCK_REMOTE_EVENT' unless %w[RECENT_REPLACED_LOG_HINT RECENT_UNCHANGED_LOG_HINT].include?(event)
    return 'BLOCK_DISK_MISMATCH' unless disk == 'MATCH'
    'BLOCK_CORE_MEMORY_UNVERIFIED'
  end

  def run
    values = %w[auto_update config_auto_update_mode config_update_week_time auto_update_time]
             .to_h { |k| [k, AiRefreshSchedule.uci_read(k)] }
    status = AiRefreshSchedule.status(values)
    daily = status['auto_update'] == 'ENABLED' && status['mode'] == 'APPOINTMENT' && status['schedule'] == 'DAILY'
    sched = daily ? 'ENABLED_DAILY' : 'OTHER'
    cron_text = safe_read('/etc/crontabs/root', 128_000)
    cron = cron_text.nil? ? 'UNAVAILABLE' : cron_matches?(cron_text, values['auto_update_time'], values['config_update_week_time']) ? 'MATCH' : 'MISMATCH'
    event = latest_event(safe_read('/tmp/openclash.log', 512_000, true), target_alias)
    disk = disk_match
    puts "SCHEDULE=#{sched} CRON_INSTALLED=#{cron}"
    puts "TARGET_SUBSCRIPTION_EVENT=#{event}"
    puts "SOURCE_RUNTIME_DISK_DEFINITIONS=#{disk}"
    puts "AI_REFRESH_GATE=#{gate(sched: sched, cron: cron, event: event, disk: disk)}"
    puts 'CORE_MEMORY_RELOAD=UNVERIFIED'
    puts 'ROUTER_CHANGES=NONE AI_SWITCH=NONE'
    0
  rescue StandardError
    puts 'AI_REFRESH_GATE=BLOCK_PROBE_UNAVAILABLE'
    2
  end
end

exit AiRefreshEventGate.run if __FILE__ == $PROGRAM_NAME
