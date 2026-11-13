#!/usr/bin/env ruby
# frozen_string_literal: true
# Inspects OpenClash refresh settings and current config provenance; NO WRITES.
# Never prints UCI secrets, airport URLs, node names, proxy IPs, config paths.
# A disk-to-disk match is NOT proof of successful remote subscription refresh.
require 'psych'

module AiRefreshSchedule
  module_function

  def status(key_values)
    auto = key_values['auto_update'].to_s
    mode = key_values['config_auto_update_mode'].to_s
    out = {
      'auto_update' => auto == '1' ? 'ENABLED' : auto == '0' ? 'DISABLED' : 'UNKNOWN',
      'mode' => 'UNKNOWN',
      'schedule' => 'UNKNOWN'
    }
    return out if out['auto_update'] != 'ENABLED'
    if mode == '0'
      out['mode'] = 'APPOINTMENT'
      week = key_values['config_update_week_time'].to_s
      out['schedule'] = week == '*' ? 'DAILY' : week.match?(/\A[0-6]\z/) ? 'WEEKLY' : 'UNKNOWN'
    elsif mode == '1'
      out['mode'] = 'LOOP'
      raw = key_values['config_update_interval'].to_s
      out['schedule'] = raw.match?(/\A[1-9]\d*\z/) && raw.to_i.between?(1, 10_080) ? 'PERIODIC' : 'UNKNOWN'
    end
    out
  end

  def age_bucket(mtime, now = Time.now)
    diff = now - mtime
    diff < 0 ? 'FUTURE' : diff < 86_400 ? 'LT24H' : diff < 604_800 ? 'LT7D' : 'OLDER'
  end

  def safe_source_file(selected)
    return nil unless selected.is_a?(String) && !selected.empty?
    root = '/etc/openclash/config/'
    path = File.expand_path(selected.start_with?('/') ? selected : File.join(root, selected))
    return nil unless path.start_with?(root) && File.file?(path) && File.size(path).between?(1, 20_000_000)
    return nil unless File.realpath(path).start_with?(root)
    path
  rescue StandardError
    nil
  end

  def live_core_config
    Dir['/proc/[0-9]*/cmdline'].each do |f|
      begin
        pid = f.split('/')[2]
        exe = File.readlink("/proc/#{pid}/exe")
        next unless exe.start_with?('/etc/openclash/core/')
        argv = File.binread(f).split("\0")
        next if argv.any? { |x| x.include?('/tmp/openclash-ai-') || x.include?('/tmp/openclash-probe-') }
        cwd = File.readlink("/proc/#{pid}/cwd")
        pos = argv.index('-d')
        dir = File.expand_path(pos ? argv[pos + 1] : cwd, cwd)
        pos = argv.index('-f')
        path = File.expand_path(pos ? argv[pos + 1] : 'config.yaml', dir)
        return path if File.file?(path) && File.size(path).between?(1, 20_000_000)
      rescue StandardError
        next
      end
    end
    nil
  end

  def disk_definitions_match?(left, right)
    a = Psych.safe_load(File.binread(left), aliases: false)
    b = Psych.safe_load(File.binread(right), aliases: false)
    raise 'no embedded proxies' unless a.is_a?(Hash) && b.is_a?(Hash) && a['proxies'].is_a?(Array) && b['proxies'].is_a?(Array)
    a['proxies'] == b['proxies']
  end

  def uci_read(key)
    IO.popen(['uci', '-q', 'get', "openclash.config.#{key}"], err: File::NULL) { |io| io.read.to_s.strip }
  rescue StandardError
    ''
  end

  def run
    keys = %w[auto_update config_auto_update_mode config_update_week_time auto_update_time config_update_interval]
    values = keys.to_h { |k| [k, uci_read(k)] }
    sched = status(values)
    puts "SCHEDULE_AUTO_UPDATE=#{sched['auto_update']} MODE=#{sched['mode']} CADENCE=#{sched['schedule']}"
    puts 'SCHEDULE_SETTINGS=READ_ONLY'
    source = safe_source_file(uci_read('config_path'))
    live = live_core_config
    puts "SOURCE_DISK=#{source ? 'READABLE' : 'UNAVAILABLE'} RUNTIME_CONFIG_DISK=#{live ? 'READABLE' : 'UNAVAILABLE'}"
    puts "SOURCE_FILE_AGE=#{source ? age_bucket(File.mtime(source)) : 'UNAVAILABLE'}"
    matched = if source && live
      begin
        disk_definitions_match?(source, live) ? 'MATCH' : 'DIFFER'
      rescue StandardError
        'UNAVAILABLE'
      end
    else
      'UNAVAILABLE'
    end
    puts "SOURCE_RUNTIME_DISK_DEFINITIONS=#{matched}"
    puts 'REMOTE_UPDATE_SUCCESS=UNVERIFIED'
    puts 'Mihomo_RELOAD_CONFIRMED=NO'
    puts 'AI_MONITOR_INSTALLED=NO'
    # No candidate is activated by this tool. Never read logs with raw URLs.
    0
  rescue StandardError
    puts 'READONLY_SCHEDULE=UNAVAILABLE_NO_PRIVATE_OUTPUT'
    2
  end
end

if __FILE__ == $PROGRAM_NAME
  exit AiRefreshSchedule.run
end
