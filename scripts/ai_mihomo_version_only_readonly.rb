#!/usr/bin/env ruby
# frozen_string_literal: true
# iStoreOS real 2026-11-14 15:02: core unique and configured; ONLY -v UNKNOWN.
# Zero requires. Read-only version-only probe with anonymous failure classes.
# Never prints executable paths, PID, process argv, raw stderr, credentials.
module AiCoreVersionOnly
  module_function
  CORE_ROOT = '/etc/openclash/core/'

  def candidate_pid
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
        i = argv.index('-f')
        cfg = i && argv[i + 1]
        cfg ||= argv.find { |v| v.start_with?('-f=') }&.split('=', 2)&.last
        d = argv.index('-d')
        dir = (d && argv[d + 1]) ||
              argv.find { |v| v.start_with?('-d=') }&.split('=', 2)&.last
        dir = File.expand_path(dir || cwd, cwd)
        cfg = File.expand_path(cfg || 'config.yaml', dir)
        next unless File.file?(cfg) && File.size(cfg).between?(1, 20_000_000)
        matches << pid
      rescue StandardError
        next
      end
    end
    matches.size == 1 ? matches.first : nil
  end

  def extract_version(s)
    return nil unless s.is_a?(String) && s.bytesize <= 8192
    m = s.match(/\b[vV]?(\d{1,3}\.\d{1,3}\.\d{1,3})(?:[-+][A-Za-z0-9._-]+)?\b/)
    m && m[1]
  end

  def version_probe(command, seconds: 3.0)
    # Does NOT suppress stderr. The old probe redirected stderr to /dev/null
    # and hid the distinction between malformed version and command failure.
    # /bin/sh uses only core BusyBox functionality, with an exact argv path
    # supplied by caller, never an untrusted user-provided remote command.
    raw = +''
    handle = nil
    begin
      handle = IO.popen(command)
      start = Time.now.to_f
      loop do
        remaining = seconds - (Time.now.to_f - start)
        return ['HOLD_VERSION_TIMEOUT', nil] if remaining <= 0
        return ['HOLD_VERSION_OUTPUT_TOO_LONG', nil] if raw.bytesize > 8192
        ready = IO.select([handle], nil, nil, remaining)
        return ['HOLD_VERSION_TIMEOUT', nil] unless ready
        begin
          part = handle.read_nonblock(512)
          raw << part
        rescue IO::WaitReadable
          next
        rescue EOFError
          break
        end
      end
      version = extract_version(raw)
      return ['VERSION_IDENTIFIED', version] if version
      return ['HOLD_VERSION_EMPTY_OUTPUT', nil] if raw.empty?
      ['HOLD_VERSION_FORMAT_UNRECOGNIZED', nil]
    rescue Errno::EACCES, Errno::ENOENT
      ['HOLD_VERSION_EXEC_UNAVAILABLE', nil]
    rescue StandardError
      ['HOLD_VERSION_RUBY_RUNTIME', nil]
    ensure
      if handle
        begin
          Process.kill('KILL', handle.pid)
        rescue Errno::ESRCH, Errno::ECHILD
        end
        begin
          handle.close
        rescue IOError, Errno::ECHILD
        end
      end
    end
  end

  def run
    puts 'MIHOMO_VERSION_ONLY=START READ_ONLY=YES'
    pid = candidate_pid
    unless pid
      puts 'MIHOMO_VERSION_RESULT=HOLD_CORE_NOT_UNIQUE'
      puts 'PRODUCTION_WRITES=NONE AUTO_SWITCH=OFF'
      return
    end
    # PID is digits from /proc. Never echo PID or command string.
    unless pid.match?(/\A\d+\z/)
      puts 'MIHOMO_VERSION_RESULT=HOLD_BAD_PID'
      puts 'PRODUCTION_WRITES=NONE AUTO_SWITCH=OFF'
      return
    end
    result, version = version_probe([
      '/bin/sh', '-c', "exec /proc/#{pid}/exe -v 2>&1"
    ])
    puts "MIHOMO_VERSION_RESULT=#{result}"
    puts "MIHOMO_VERSION=#{version || 'UNAVAILABLE'}"
    puts 'PRODUCTION_WRITES=NONE AUTO_SWITCH=OFF'
  rescue StandardError
    puts 'MIHOMO_VERSION_RESULT=HOLD_VERSION_READ_ONLY_FAILURE'
    puts 'PRODUCTION_WRITES=NONE AUTO_SWITCH=OFF'
  end
end

AiCoreVersionOnly.run if __FILE__ == $PROGRAM_NAME
