#!/usr/bin/env ruby
# frozen_string_literal: true
# iStoreOS 2026-11-14 15:22: real core -v prints non-semver. Version string
# is NOT the gate. Test actual installed core native listener configuration
# grammar with a purely synthetic private /tmp fixture. No Ruby require.
#
# No real airport source, passwords, existing config or subscription is read.
# No controller calls, route changes, listener activation, daemon or schedule.
# Does temporarily spawn one -t parse-only child, using its own -d directory.
module AiNotebookNativeCapability
  module_function

  CORE_ROOT = '/etc/openclash/core/'
  LIMIT_SECONDS = 12.0

  def synthetic_yaml
    <<~YAML
      mode: rule
      allow-lan: false
      log-level: silent
      proxies:
        - name: SYNTHETIC_NO_NETWORK
          type: http
          server: 192.0.2.1
          port: 8080
      proxy-groups:
        - name: __AI_NOTEBOOK_PROBE_ONLY__
          type: select
          proxies:
            - REJECT
            - SYNTHETIC_NO_NETWORK
      listeners:
        - name: ai-notebook-probe-only
          type: http
          listen: 127.0.0.1
          port: 17881
          proxy: __AI_NOTEBOOK_PROBE_ONLY__
      rules:
        - MATCH,REJECT
    YAML
  end

  def find_running_core_pid
    matches = []
    Dir['/proc/[0-9]*/cmdline'].each do |file|
      begin
        pid = file.split('/')[2]
        exe = File.readlink("/proc/#{pid}/exe")
        next unless exe.start_with?(CORE_ROOT)
        argv = File.binread(file).split("\0")
        next if argv.any? { |v|
          v.include?('/tmp/openclash-ai-') ||
            v.include?('/tmp/openclash-probe-') ||
            v.include?('/tmp/oc-ai-')
        }
        cwd = File.readlink("/proc/#{pid}/cwd")
        fi = argv.index('-f')
        di = argv.index('-d')
        cfg = (fi && argv[fi + 1]) ||
              argv.find { |v| v.start_with?('-f=') }&.split('=', 2)&.last
        dir = (di && argv[di + 1]) ||
              argv.find { |v| v.start_with?('-d=') }&.split('=', 2)&.last
        cfg = File.expand_path(cfg || 'config.yaml', File.expand_path(dir || cwd, cwd))
        next unless File.file?(cfg) && File.size(cfg).between?(1, 20_000_000)
        matches << pid
      rescue StandardError
        next
      end
    end
    matches.size == 1 ? matches.first : nil
  end

  def bounded_native_test(argv, seconds: LIMIT_SECONDS)
    child = nil
    begin
      child = Process.spawn(*argv, out: File::NULL, err: File::NULL)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      loop do
        done, status = Process.waitpid2(child, Process::WNOHANG)
        if done
          child = nil
          return status.success? ? 'NATIVE_LISTENER_SYNTAX_PASS' : 'HOLD_NATIVE_LISTENER_SYNTAX_REJECTED'
        end
        return 'HOLD_NATIVE_LISTENER_TEST_TIMEOUT' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.1
      end
    rescue Errno::ENOENT, Errno::EACCES
      'HOLD_NATIVE_EXEC_UNAVAILABLE'
    rescue StandardError
      'HOLD_NATIVE_TEST_RUNTIME'
    ensure
      if child
        begin
          Process.kill('KILL', child)
        rescue Errno::ESRCH, Errno::ECHILD
        end
        begin
          Process.waitpid(child)
        rescue Errno::ECHILD
        end
      end
    end
  end

  def temporary_dir
    3.times do
      suffix = File.binread('/dev/urandom', 8).unpack('H*').first
      path = "/tmp/ai_nb_native_#{suffix}"
      begin
        Dir.mkdir(path, 0700)
        return path
      rescue Errno::EEXIST
        next
      end
    end
    nil
  end

  def run
    puts 'MIHOMO_NATIVE_CAPABILITY=START TEST_ONLY=YES'
    pid = find_running_core_pid
    unless pid && pid.match?(/\A\d+\z/)
      puts 'NATIVE_CAPABILITY=HOLD_CORE_NOT_UNIQUE'
      puts 'PRODUCTION_CONFIG=UNCHANGED AUTO_SWITCH=OFF'
      return
    end
    dir = nil
    result = 'HOLD_NATIVE_TEST_RUNTIME'
    cleanup = 'YES'
    begin
      dir = temporary_dir
      if dir
        file = "#{dir}/synthetic.yaml"
        File.open(file, File::WRONLY | File::CREAT | File::EXCL, 0600) do |f|
          f.write(synthetic_yaml)
        end
        # Never use real OpenClash configuration, -d working directory or
        # subscription in this test. -t should only parse the fake fixture.
        result = bounded_native_test([
          "/proc/#{pid}/exe", '-t', '-d', dir, '-f', file
        ])
      else
        result = 'HOLD_PRIVATE_TMP_UNAVAILABLE'
      end
    rescue StandardError
      result = 'HOLD_PRIVATE_TMP_UNAVAILABLE'
    ensure
      if dir
        begin
          File.delete("#{dir}/synthetic.yaml") if File.file?("#{dir}/synthetic.yaml")
          Dir.rmdir(dir)
        rescue StandardError
          cleanup = 'FAILED'
          result = 'HOLD_PRIVATE_TMP_CLEANUP'
        end
      end
    end
    puts "NATIVE_CAPABILITY=#{result}"
    puts "TEMP_CLEANUP=#{cleanup}"
    puts 'REAL_AI_BUSINESS=UNKNOWN LISTENER_INSTALLED=NO'
    puts 'PRODUCTION_CONFIG=UNCHANGED AUTO_SWITCH=OFF'
  rescue StandardError
    puts 'NATIVE_CAPABILITY=HOLD_NATIVE_READ_ONLY_RUNTIME'
    puts 'PRODUCTION_CONFIG=UNCHANGED AUTO_SWITCH=OFF'
  end
end

AiNotebookNativeCapability.run if __FILE__ == $PROGRAM_NAME
