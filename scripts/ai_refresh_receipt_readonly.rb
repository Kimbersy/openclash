#!/usr/bin/env ruby
# frozen_string_literal: true
# ANONYMOUS OpenClash subscription update log classifier. Read-only.
# This observes *reported* outcomes, NOT a verified download, runtime reload
# or proof that the currently-running core has the new connection credentials.
require 'time'

module AiRefreshReceipt
  module_function

  def classified_log(text, alias_name:, now: Time.now, max_age_seconds: 48 * 3600)
    raise ArgumentError, 'invalid alias' unless alias_name.is_a?(String) &&
      !alias_name.empty? && alias_name.bytesize <= 200 &&
      !alias_name.match?(/[\r\n\x00]/)
    raise ArgumentError, 'invalid log text' unless text.is_a?(String)
    raise ArgumentError, 'invalid clock' unless now.is_a?(Time)

    start_key = "开始更新配置文件〖#{alias_name}〗"
    success_key = "配置文件〖#{alias_name}〗更新成功"
    same_key = "配置文件〖#{alias_name}〗没有更新"
    error_keys = ["配置文件〖#{alias_name}〗订阅失败",
                  "配置文件〖#{alias_name}〗更新失败",
                  "配置文件〖#{alias_name}〗替换失败",
                  "配置文件〖#{alias_name}〗下载失败"]
    start_at = nil
    completed_at = nil
    observed = 'NO_MATCHING_ATTEMPT'
    text.each_line do |line|
      next unless (m = /\A(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/.match(line))
      stamp = begin
        Time.strptime(m[1], '%Y-%m-%d %H:%M:%S')
      rescue ArgumentError
        nil
      end
      next unless stamp && stamp <= now + 300 && stamp >= now - (30 * 86_400)
      if line.include?(start_key)
        start_at = stamp
        completed_at = nil
        observed = 'IN_PROGRESS'
        next
      end
      next unless start_at && stamp >= start_at && stamp - start_at < 3600
      if line.include?(success_key)
        observed = 'LOG_REPORTED_UPDATED'
        completed_at = stamp
      elsif line.include?(same_key)
        observed = 'LOG_REPORTED_NO_CHANGE'
        completed_at = stamp
      elsif error_keys.any? { |key| line.include?(key) }
        observed = 'LOG_REPORTED_ERROR'
        completed_at = stamp
      end
    end
    return {'result'=>'NO_MATCHING_ATTEMPT', 'age'=>'UNKNOWN'} unless start_at
    return {'result'=>'LOG_STALE', 'age'=>'OLDER'} if now - start_at > max_age_seconds
    age = now - start_at < 86_400 ? 'LT24H' : 'LT48H'
    {'result'=>observed, 'age'=>age, 'completed'=>(!completed_at.nil?)}
  end

  def tail_private_log
    path = '/tmp/openclash.log'
    return nil unless File.file?(path) && File.readable?(path)
    # Never log/show any raw lines. Avoid unbounded memory on full router logs.
    File.open(path, 'rb') do |f|
      f.seek([-1_048_576, -f.size].max, IO::SEEK_END)
      body = f.read(1_048_576).to_s
      body.force_encoding(Encoding::UTF_8)
      body.valid_encoding? ? body : body.scrub('')
    end
  rescue StandardError
    nil
  end

  def run
    # The previously verified deployment has exactly one enabled subscription.
    # Recheck this rather than silently applying another alias's log.
    sections = IO.popen(['uci','-q','show','openclash'], err: File::NULL) { |io| io.read.to_s }
                    .scan(/^openclash\.([^.=]+)=config_subscribe\s*$/).flatten.uniq
    raise 'subscription sections changed' unless sections.size == 1
    base = "openclash.#{sections.first}"
    enabled = IO.popen(['uci','-q','get',base+'.enabled'], err: File::NULL) { |io| io.read.to_s.strip }
    raise 'subscription disabled' unless enabled == '1'
    name = IO.popen(['uci','-q','get',base+'.name'], err: File::NULL) { |io| io.read.to_s.strip }
    name = 'config' if name.empty?
    content = tail_private_log
    puts "REFRESH_LOG=READ_ONLY"
    if content.nil?
      puts 'LOG_SOURCE=UNAVAILABLE'
      puts 'LOG_ATTEMPT=UNKNOWN AGE=UNKNOWN'
    else
      info = classified_log(content, alias_name: name)
      puts 'LOG_SOURCE=READABLE'
      puts "LOG_ATTEMPT=#{info.fetch('result')} AGE=#{info.fetch('age')}"
    end
    puts 'REMOTE_UPDATE_SUCCESS=LOG_ONLY_NOT_PROVEN'
    puts 'Mihomo_MEMORY_LOADED=NOT_VERIFIED'
    puts 'AI_POOL_REFRESH_GATE=HOLD'
    0
  rescue StandardError
    puts 'READONLY_LOG_PROBE=UNAVAILABLE_NO_PRIVATE_OUTPUT'
    2
  end
end

if __FILE__ == $PROGRAM_NAME
  exit AiRefreshReceipt.run
end
