#!/usr/bin/env ruby
# frozen_string_literal: true
# Read-only preflight. Never forks, creates sessions, reads URLs or starts updates.
module AiUnattendedScheduleCapabilityReadOnly
  module_function
  KEYS = %w[auto_update config_auto_update_mode config_update_week_time auto_update_time].freeze

  def classify(settings)
    return ['HOLD_SCHEDULE_NOT_DAILY', 'UNKNOWN'] unless settings['auto_update']=='1' &&
      settings['config_auto_update_mode']=='0' && settings['config_update_week_time']=='*'
    raw=settings['auto_update_time']
    return ['HOLD_UPDATE_HOUR_UNDECLARED', 'UNKNOWN'] unless
      raw.is_a?(String) && raw.match?(/\A(?:[0-9]|1[0-9]|2[0-3])\z/)
    ['DAILY_HOUR_DECLARED_ONLY',format('%02d',raw.to_i)]
  end

  def read_uci(key)
    return nil unless KEYS.include?(key)
    v=IO.popen(['uci','-q','get',"openclash.config.#{key}"],
      err:File::NULL){|io|io.read(40).to_s.strip}
    return nil unless $?.success? && v.bytesize<=32 && v.match?(/\A[0-9*]*\z/)
    v
  rescue StandardError
    nil
  end

  def run
    settings=KEYS.to_h{|k|[k,read_uci(k)]}
    state,hour=classify(settings)
    puts 'UNATTENDED_SCHEDULE_PREFLIGHT=START NO_HTTP=YES'
    puts "SCHEDULE_RESULT=#{state}"
    puts "UCI_AUTO_UPDATE_HOUR=#{hour}"
    puts "RUBY_FORK_METHOD=#{Process.respond_to?(:fork) ? 'PRESENT' : 'NOT_PRESENT'}"
    puts "RUBY_SETSID_METHOD=#{Process.respond_to?(:setsid) ? 'PRESENT' : 'NOT_PRESENT'}"
    puts 'UPDATE_EXECUTION=NOT_VERIFIED DEVICE_LOCAL_TIMEZONE=NOT_VERIFIED'
    puts 'DETACHED_SESSION=NOT_STARTED CRON_PROCD=UNCHANGED'
    puts 'SUBSCRIPTION_URLS_AND_SECRETS=NOT_READ_OR_EMITTED'
    puts 'PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  rescue StandardError
    puts 'SCHEDULE_RESULT=HOLD_READONLY_PREFLIGHT'
  end
end

AiUnattendedScheduleCapabilityReadOnly.run if __FILE__==$PROGRAM_NAME
