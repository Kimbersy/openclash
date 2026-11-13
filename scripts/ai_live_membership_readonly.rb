#!/usr/bin/env ruby
# frozen_string_literal: true
# Read-only Mihomo GET /proxies name-catalog probe.
# NEVER prints proxy names, real IPs, server/port, credentials or controller secrets.
# NEVER calls PUT/DELETE, triggers a refresh, or changes selections.
# Controller endpoint must be an fd/socket owned by the actual OpenClash core.
require 'psych'
require_relative 'ai_refresh_schedule_readonly'

module AiLiveMembership
  module_function

  GROUP_TYPES = %w[Selector URLTest Fallback LoadBalance].freeze
  BUILTIN_NAMES = %w[DIRECT REJECT REJECT-DROP PASS COMPATIBLE GLOBAL].freeze

  def check_names(expected, result)
    return 'BAD_DISK_NODES' unless expected.is_a?(Array) && expected.all? { |x| x.is_a?(Hash) && x['name'].is_a?(String) && !x['name'].empty? }
    names = expected.map { |n| n['name'] }
    return 'BAD_DISK_NODES' if names.uniq.size != names.size
    return 'BAD_API_PAYLOAD' unless result.is_a?(Hash) && result['proxies'].is_a?(Hash)
    proxies = result['proxies']
    return 'BAD_API_PAYLOAD' unless proxies.all? { |name, value| name.is_a?(String) && value.is_a?(Hash) && value['type'].is_a?(String) }
    leaf_names = proxies.filter_map do |name, data|
      next if GROUP_TYPES.include?(data['type']) || BUILTIN_NAMES.include?(name)
      name
    end
    return 'EXACT_NAMES_ONLY' if leaf_names.uniq.sort == names.sort
    return 'EXPECTED_MISSING' unless (names - leaf_names).empty?
    'UNEXPECTED_EXTRA_NAMES'
  end

  # Anonymous counters only. Additional leaf entries are quarantined: a
  # complete expected-name subset is not proof of the latest config reload,
  # and unknown extra entries must never inherit AI service qualifications.
  def name_coverage(expected, result)
    return nil unless expected.is_a?(Array) && expected.all? { |x|
      x.is_a?(Hash) && x['name'].is_a?(String) && !x['name'].empty?
    }
    names = expected.map { |x| x['name'] }
    return nil unless names.uniq.size == names.size
    return nil unless result.is_a?(Hash) && result['proxies'].is_a?(Hash)
    proxies = result['proxies']
    return nil unless proxies.all? { |name, value|
      name.is_a?(String) && value.is_a?(Hash) && value['type'].is_a?(String)
    }
    leaf = proxies.filter_map do |name, data|
      next if GROUP_TYPES.include?(data['type']) || BUILTIN_NAMES.include?(name)
      name
    end
    {expected: names.length, present: (names & leaf).length,
     extra_untrusted: (leaf - names).length}
  end

  def flag(argv, key)
    idx = argv.index(key)
    return argv[idx + 1] if idx && idx + 1 < argv.length
    argv.find { |s| s.start_with?(key + '=') }&.split('=', 2)&.last
  end

  def candidate_core
    matches = []
    Dir['/proc/[0-9]*/cmdline'].each do |f|
      begin
        pid = f.split('/')[2]
        exe = File.readlink("/proc/#{pid}/exe")
        next unless exe.start_with?('/etc/openclash/core/')
        argv = File.binread(f).split("\0")
        next if argv.any? { |a| a.include?('/tmp/openclash-ai-') || a.include?('/tmp/openclash-probe-') || a.include?('/tmp/oc-ai-') }
        cwd = File.readlink("/proc/#{pid}/cwd")
        dir = File.expand_path(flag(argv, '-d') || cwd, cwd)
        raw = flag(argv, '-f') || 'config.yaml'
        conf = File.expand_path(raw, dir)
        next unless File.file?(conf) && File.size(conf).between?(1, 20_000_000)
        matches << [pid, argv, conf]
      rescue StandardError
        next
      end
    end
    return nil unless matches.size == 1
    matches.first
  end

  def local_controller(addr)
    # HTTP to explicit 127.0.0.1 only; never send secrets to a remote endpoint.
    m = /\A(?:127\.0\.0\.1|0\.0\.0\.0):([0-9]{1,5})\z/.match(addr.to_s)
    return nil unless m && m[1].to_i.between?(1, 65_535)
    m[1].to_i
  end

  def owns_listener?(pid, port)
    inode_set = %w[/proc/net/tcp /proc/net/tcp6].flat_map do |path|
      next [] unless File.file?(path)
      File.foreach(path).drop(1).filter_map do |line|
        cols = line.split
        next unless cols.length > 9 && cols[3] == '0A' && cols[1].split(':').last.to_i(16) == port
        cols[9]
      end
    end
    return false if inode_set.empty?
    Dir["/proc/#{pid}/fd/*"].any? do |f|
      begin
        inode_set.include?(File.readlink(f)[/\Asocket:\[(\d+)\]\z/, 1])
      rescue StandardError
        false
      end
    end
  rescue StandardError
    false
  end

  def anonymous_catalog(source, runtime, live_result)
    base = Psych.safe_load(File.binread(source), aliases: false)
    core = Psych.safe_load(File.binread(runtime), aliases: false)
    return ['DISK_UNAVAILABLE', 0] unless base.is_a?(Hash) && core.is_a?(Hash)
    return ['PROVIDERS_NOT_SUPPORTED_BY_THIS_PROBE', 0] if
      (base['proxy-providers'].is_a?(Hash) && !base['proxy-providers'].empty?) ||
      (core['proxy-providers'].is_a?(Hash) && !core['proxy-providers'].empty?)
    return ['DISK_DIFFERENT', 0] unless base['proxies'].is_a?(Array) && base['proxies'] == core['proxies']
    result = check_names(base['proxies'], live_result)
    [result, base['proxies'].size]
  rescue StandardError
    ['DISK_UNAVAILABLE', 0]
  end

  def api_read(secret, port)
    # Read secret only in Ruby memory; pass curl header over stdin, not argv.
    return nil unless secret.is_a?(String) && secret.bytesize <= 512 && !secret.match?(/[\x00-\x1f]/)
    args = ['curl', '-q', '--noproxy', '*', '--silent', '--fail',
            '--connect-timeout', '2', '--max-time', '7', '--max-filesize', '3000000',
            '--config', '-', "http://127.0.0.1:#{port}/proxies"]
    payload = ''
    IO.popen(args, 'r+', err: File::NULL) do |io|
      if !secret.empty?
        escaped = secret.gsub(/[\\"]/) { |c| '\\' + c }
        io.write("header = \"Authorization: Bearer #{escaped}\"\n")
      end
      io.close_write
      payload = io.read(3_000_001)
    end
    return nil unless $?.success? && payload.bytesize.between?(2, 3_000_000)
    data = Psych.safe_load(payload, aliases: false)
    data.is_a?(Hash) ? data : nil
  rescue StandardError
    nil
  end

  def run
    source = AiRefreshSchedule.safe_source_file(AiRefreshSchedule.uci_read('config_path'))
    core = candidate_core
    unless source && core
      puts 'LIVE_API=BLOCKED_SOURCE_OR_CORE_NOT_UNIQUE'
      return 0
    end
    pid, argv, config = core
    parsed = Psych.safe_load(File.binread(config), aliases: false)
    unless parsed.is_a?(Hash)
      puts 'LIVE_API=BLOCKED_RUNTIME_CONFIG_INVALID'
      return 0
    end
    address = flag(argv, '-ext-ctl') || parsed['external-controller']
    secret = flag(argv, '-secret') || parsed['secret'] || ''
    port = local_controller(address)
    unless port
      puts 'LIVE_API=BLOCKED_UNSUPPORTED_CONTROLLER_ADDRESS'
      return 0
    end
    unless owns_listener?(pid, port)
      puts 'LIVE_API=BLOCKED_UNVERIFIED_SOCKET_OWNER'
      return 0
    end
    data = api_read(secret, port)
    unless data
      puts 'LIVE_API=UNAVAILABLE_NO_PUBLIC_DETAILS'
      return 0
    end
    result, count = anonymous_catalog(source, config, data)
    puts 'LIVE_API=READ_ONLY_GET_SUCCESS'
    puts "LIVE_API_AUTH_MODE=#{secret.empty? ? 'NO_SECRET_CONFIGURED' : 'BEARER_TOKEN_ACCEPTED'}"
    puts "LIVE_PROXY_NAME_COVERAGE=#{result} EXPECTED_DISK_NODES=#{count}"
    if %w[EXACT_NAMES_ONLY UNEXPECTED_EXTRA_NAMES EXPECTED_MISSING].include?(result)
      source_data = Psych.safe_load(File.binread(source), aliases: false)
      counts = name_coverage(source_data['proxies'], data)
      if counts && counts[:expected] == count
        puts "LIVE_EXPECTED_NAME_PRESENT=#{counts[:present]} EXTRA_UNTRUSTED_NAMES=#{counts[:extra_untrusted]}"
        puts 'AI_EXTRA_NAMES_ELIGIBLE=NO'
      end
    end
    puts 'LIVE_FULL_CREDENTIALS_MATCH=UNVERIFIED'
    puts 'REMOTE_SUBSCRIPTION_UPDATE_SUCCESS=UNVERIFIED'
    puts 'MIHOMO_RELOAD_FOR_LATEST_UPDATE=UNVERIFIED'
    puts 'AI_MONITOR_INSTALLED=NO'
    0
  rescue StandardError
    puts 'LIVE_API=UNAVAILABLE_NO_PRIVATE_OUTPUT'
    0
  end
end

exit AiLiveMembership.run if __FILE__ == $PROGRAM_NAME
