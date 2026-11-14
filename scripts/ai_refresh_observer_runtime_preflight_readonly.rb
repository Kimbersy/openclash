#!/usr/bin/env ruby
# frozen_string_literal: true
# One-shot target Ruby capability gate BEFORE any passive observer deployment.
# No require, OpenClash edits, network or background process; only a dedicated
# private /tmp flock inode is created and deliberately retained to avoid races.
module AiRefreshObserverRuntimePreflight
  module_function
  LOCK = '/tmp/ai_refresh_observer_preflight.lock'
  def assess
    out = {
      'RUBY_FILE_NOFOLLOW' => 'HOLD',
      'RUBY_PRIVATE_FLOCK' => 'HOLD',
      'RUBY_MONOTONIC_CLOCK' => 'HOLD',
      'RUBY_SIGNAL_TRAP' => 'HOLD'
    }
    if File.const_defined?(:NOFOLLOW)
      out['RUBY_FILE_NOFOLLOW'] = 'PASS'
      begin
        File.umask(0077)
        a = File.open(LOCK, File::RDWR|File::CREAT|File::NOFOLLOW, 0600)
        st = a.stat
        if st.file? && st.uid == Process.uid && st.nlink == 1 &&
           (st.mode & 0o077) == 0 && a.flock(File::LOCK_EX|File::LOCK_NB)
          b = File.open(LOCK, File::RDWR|File::NOFOLLOW, 0600)
          begin
            out['RUBY_PRIVATE_FLOCK'] = 'PASS' unless b.flock(File::LOCK_EX|File::LOCK_NB)
          ensure
            b.close
          end
        end
      rescue StandardError
        # Fail closed. No private file contents or exception text printed.
      ensure
        a&.close
      end
    end
    begin
      v1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      v2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      out['RUBY_MONOTONIC_CLOCK'] = 'PASS' if v1.is_a?(Numeric) && v2 >= v1
    rescue StandardError
      # No fallback to wall clock for the observation lifetime.
    end
    begin
      old = trap('TERM') {}
      trap('TERM', old)
      out['RUBY_SIGNAL_TRAP'] = 'PASS'
    rescue StandardError
      # Never send a signal or leave a background process.
    end
    out
  end
  def run
    puts 'PASSIVE_RUNTIME_PREFLIGHT=START ONE_SHOT_NO_HTTP=YES'
    result = assess
    result.each {|name, value| puts "#{name}=#{value}"}
    puts "PASSIVE_RUNTIME_PREFLIGHT_RESULT=#{result.values.all?{|v|v=='PASS'} ? 'PRIMITIVES_AVAILABLE_ONLY' : 'HOLD_RUNTIME_CAPABILITY'}"
    puts 'UPDATER_CONTENT=NOT_READ REFRESH_COMMIT=NOT_VERIFIED'
    puts 'LISTENER_INSTALLED=NO PASSIVE_OBSERVER_INSTALLED=NO'
    puts 'PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN AUTO_SWITCH=OFF'
  rescue StandardError
    puts 'PASSIVE_RUNTIME_PREFLIGHT_RESULT=HOLD_RUNTIME'
  end
end

AiRefreshObserverRuntimePreflight.run if __FILE__ == $PROGRAM_NAME
