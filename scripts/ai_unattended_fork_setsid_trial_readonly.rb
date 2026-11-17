#!/usr/bin/env ruby
# frozen_string_literal: true
# One-shot safety trial for fork/setsid on the real iStoreOS Ruby.
# No require, UCI, OpenClash, subscription, proxy, network, cron or daemon.
# A single child must exit and be reaped before this script returns.
module AiUnattendedForkSetsidTrialReadOnly
  module_function
  MAX_SECONDS = 4

  def run
    puts 'FORK_SESSION_TRIAL=START ONE_SHOT=YES NO_HTTP=YES'
    unless Process.respond_to?(:fork) && Process.respond_to?(:setsid) &&
      Process.respond_to?(:getsid) && Process.respond_to?(:waitpid2) &&
      Process.const_defined?(:WNOHANG)
      puts 'FORK_SESSION_TRIAL_RESULT=HOLD_METHOD_UNAVAILABLE'
      return
    end
    r=nil
    w=nil
    child_pid=nil
    reaped=false
    begin
      r,w=IO.pipe
      child_pid=Process.fork do
        r.close
        success=false
        begin
          sid=Process.setsid
          success=(sid==Process.pid && Process.getsid(0)==sid)
        rescue StandardError
          success=false
        end
        begin
          w.write(success ? '1' : '0')
          w.flush
        rescue StandardError
          success=false
        ensure
          w.close
        end
        exit!(success ? 0 : 1)
      end
      w.close
      deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+MAX_SECONDS
      status=nil
      while Process.clock_gettime(Process::CLOCK_MONOTONIC)<deadline
        found=Process.waitpid2(child_pid,Process::WNOHANG)
        if found
          status=found.last
          reaped=true
          break
        end
        sleep(0.04)
      end
      if reaped
        signal=r.read(2)
        if status && status.success? && signal=='1'
          puts 'FORK_SESSION_TRIAL_RESULT=CHILD_SESSION_ISOLATION_PASS'
        else
          puts 'FORK_SESSION_TRIAL_RESULT=HOLD_CHILD_SESSION_CHECK'
        end
      else
        puts 'FORK_SESSION_TRIAL_RESULT=HOLD_CHILD_TIMEOUT'
      end
    rescue StandardError
      puts 'FORK_SESSION_TRIAL_RESULT=HOLD_FORK_RUNTIME'
    ensure
      # Only our OWN unreaped direct child can be signaled; no killall or
      # PID-based guessing and no detached service ever persists.
      if child_pid && !reaped
        begin
          Process.kill('TERM',child_pid)
          15.times do
            found=Process.waitpid2(child_pid,Process::WNOHANG)
            if found
              reaped=true
              break
            end
            sleep(0.04)
          end
          unless reaped
            Process.kill('KILL',child_pid)
            Process.waitpid2(child_pid)
            reaped=true
          end
        rescue Errno::ECHILD
          reaped=true
        rescue StandardError
          # Never claim successful cleanup without a completed reap.
        end
      end
      r&.close
      w&.close
      puts "DIRECT_CHILD_REAPED=#{reaped ? 'YES' : 'NOT_CONFIRMED'}"
      puts 'BACKGROUND_SERVICE=NOT_INSTALLED CRON_PROCD=UNCHANGED'
      puts 'SUBSCRIPTION_AND_CORE=NOT_READ UPDATE_TRIGGERED=NO'
      puts 'TRUSTED_REMOTE_COMMIT=NOT_VERIFIED ALLOW_RECONCILE=NO ALLOW_SWITCH=NO'
      puts 'PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
    end
  end
end
AiUnattendedForkSetsidTrialReadOnly.run if __FILE__==$PROGRAM_NAME
