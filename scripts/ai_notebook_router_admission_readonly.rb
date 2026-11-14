#!/usr/bin/env ruby
# frozen_string_literal: true
# One-shot /proc + already-running-config admission for the native, single-core
# NotebookLM probe listener. READS ONLY; no network, config writes, curl,
# controller PUT, router restart, second core, or subscription refresh.
# NEVER print config paths, process argv, URLs, secrets, proxy names or IPs.
require 'psych'
require 'timeout'

# Keep this file self-contained for a ONE-FILE iStoreOS read-only invocation.
# Reuse the proven active-core identity rules from ai_live_membership_readonly.

module AiNotebookRouterAdmission
  module_function

  PORT = 17_881
  GROUP = '__AI_NOTEBOOK_PROBE_ONLY__'
  LISTENER = 'ai-notebook-probe-only'
  CORE_ROOT = '/etc/openclash/core/'

  def listening_ports(tcp4, tcp6)
    # Nil = /proc information unavailable. Strings are kernel tables only,
    # never user-supplied network requests.
    return nil unless tcp4.is_a?(String) && tcp6.is_a?(String)
    ports = []
    [tcp4, tcp6].each do |table|
      table.lines.drop(1).each do |line|
        fields = line.split
        next unless fields.size > 3 && fields[3] == '0A'
        value = fields[1].split(':').last
        return nil unless value && value.match?(/\A[0-9A-Fa-f]{1,4}\z/)
        ports << value.to_i(16)
      end
    end
    ports
  rescue StandardError
    nil
  end

  def read_tcp
    a = File.read('/proc/net/tcp', 2_000_000)
    # IPv6 may be disabled; absent tcp6 is different from an unreadable table.
    b = File.file?('/proc/net/tcp6') ? File.read('/proc/net/tcp6', 2_000_000) : "  sl  local_address rem_address st\n"
    listening_ports(a, b)
  rescue StandardError
    nil
  end

  def version_from_output(raw)
    return nil unless raw.is_a?(String) && raw.bytesize <= 4096
    match = raw.match(/\b(v?\d{1,3}\.\d{1,3}\.\d{1,3})\b/i)
    match && match[1].delete_prefix('v')
  end

  def cmd_flag(argv, flag)
    index = argv.index(flag)
    return argv[index + 1] if index && index + 1 < argv.length
    argv.find { |value| value.start_with?(flag + '=') }&.split('=', 2)&.last
  end

  def candidate_core
    matches = []
    Dir['/proc/[0-9]*/cmdline'].each do |file|
      begin
        pid = file.split('/')[2]
        exe = File.readlink("/proc/#{pid}/exe")
        next unless exe.start_with?(CORE_ROOT)
        argv = File.binread(file).split("\0")
        next if argv.any? { |value|
          value.include?('/tmp/openclash-ai-') ||
            value.include?('/tmp/openclash-probe-') ||
            value.include?('/tmp/oc-ai-')
        }
        cwd = File.readlink("/proc/#{pid}/cwd")
        dir = File.expand_path(cmd_flag(argv, '-d') || cwd, cwd)
        path = File.expand_path(cmd_flag(argv, '-f') || 'config.yaml', dir)
        next unless File.file?(path) && File.size(path).between?(1, 20_000_000)
        matches << [pid, path]
      rescue StandardError
        next
      end
    end
    matches.size == 1 ? matches.first : nil
  end

  def installed_version(pid)
    exe = File.readlink("/proc/#{pid}/exe")
    return nil unless exe.start_with?(CORE_ROOT)
    # This is the installed executable's -v read-only metadata, not a
    # download/upgrade. Bounded to 3 seconds and at most 4KiB of output.
    raw = Timeout.timeout(3) do
      IO.popen(["/proc/#{pid}/exe", '-v'], err: File::NULL) { |io| io.read(4097) }
    end
    version_from_output(raw)
  rescue StandardError, Timeout::Error
    nil
  end

  def config_assessment(config)
    return 'HOLD_CONFIG_INVALID' unless config.is_a?(Hash)
    groups = config['proxy-groups']
    proxies = config['proxies']
    listeners = config.fetch('listeners', [])
    return 'HOLD_CONFIG_LAYOUT' unless groups.is_a?(Array) && proxies.is_a?(Array) &&
                                       listeners.is_a?(Array)
    return 'HOLD_SOURCE_PROVIDERS_PRESENT' if config['proxy-providers'].is_a?(Hash) &&
                                               !config['proxy-providers'].empty?
    return 'HOLD_NO_LEAF_PROXIES' if proxies.empty?
    return 'HOLD_CONFIG_LAYOUT' unless groups.all? { |g|
      g.is_a?(Hash) && g['name'].is_a?(String) && g['proxies'].is_a?(Array)
    }
    return 'HOLD_CONFIG_LAYOUT' unless proxies.all? { |p|
      p.is_a?(Hash) && p['name'].is_a?(String) && p['type'].is_a?(String)
    }
    group_names = groups.map { |g| g['name'] }
    leaf_names = proxies.map { |p| p['name'] }
    return 'HOLD_DUPLICATE_OR_COLLIDING_NAMES' unless group_names.uniq.size == group_names.size &&
                                                     leaf_names.uniq.size == leaf_names.size &&
                                                     (group_names & leaf_names).empty?
    return 'HOLD_PROBE_NAME_COLLISION' if group_names.include?(GROUP) || leaf_names.include?(GROUP)
    return 'HOLD_AI_PARENT_NOT_SELECT' unless groups.count { |g|
      g['name'] == '🤖 AI' && g['type'] == 'select'
    } == 1
    return 'HOLD_UNVERIFIED_LISTENER' unless listeners.all? { |x|
      x.is_a?(Hash) && x['name'].is_a?(String) &&
        (x['port'].is_a?(Integer) || x['port'].to_s.match?(/\A\d+\z/))
    }
    return 'HOLD_PROBE_NAME_COLLISION' if listeners.any? { |x| x['name'] == LISTENER }
    local_ports = listeners.map { |x| x['port'].to_i }
    %w[port socks-port mixed-port redir-port tproxy-port].each do |key|
      next unless config.key?(key)
      value = config[key]
      return 'HOLD_UNKNOWN_CORE_PORT' unless (value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/))
      local_ports << value.to_i
    end
    return 'HOLD_CONFIG_PORT_COLLISION' if local_ports.include?(PORT)
    'CONFIG_STRUCTURALLY_READY'
  rescue StandardError
    'HOLD_CONFIG_UNAVAILABLE'
  end

  def overall(version:, ports:, config_status:)
    return 'HOLD_CORE_VERSION_UNKNOWN' if version.nil?
    return 'HOLD_LISTEN_PORT_UNKNOWN' if ports.nil?
    return 'HOLD_LISTEN_PORT_IN_USE' if ports.include?(PORT)
    return config_status unless config_status == 'CONFIG_STRUCTURALLY_READY'
    'READY_FOR_PRIVATE_COPY_NATIVE_TEST_ONLY'
  end

  def run
    puts 'NOTEBOOK_ROUTER_ADMISSION=START READ_ONLY=YES'
    core = candidate_core
    unless core
      puts 'CORE_PROCESS=NOT_UNIQUELY_IDENTIFIED'
      puts 'ADMISSION=HOLD_CORE_UNAVAILABLE PRODUCTION_WRITES=NONE'
      return 0
    end
    pid, path = core
    version = installed_version(pid)
    ports = read_tcp
    config_status = begin
      bytes = File.binread(path, 20_000_001)
      bytes.bytesize.between?(1, 20_000_000) ?
        config_assessment(Psych.safe_load(bytes, aliases: false)) : 'HOLD_CONFIG_SIZE'
    rescue StandardError
      'HOLD_CONFIG_UNAVAILABLE'
    end
    puts 'CORE_PROCESS=UNIQUE_OPENCLASH'
    puts "CORE_VERSION=#{version || 'UNAVAILABLE'}"
    puts "PORT_17881=#{ports.nil? ? 'UNKNOWN' : ports.include?(PORT) ? 'IN_USE' : 'NOT_LISTENING'}"
    puts "RUNNING_CONFIG=#{config_status}"
    puts "ADMISSION=#{overall(version: version, ports: ports, config_status: config_status)}"
    puts 'PRIVATE_COPY_TEST=NOT_RUN'
    puts 'NODE_BUSINESS=UNKNOWN AUTO_SWITCH=OFF PRODUCTION_WRITES=NONE'
    0
  rescue StandardError
    puts 'ADMISSION=HOLD_READ_ONLY_NO_PRIVATE_OUTPUT PRODUCTION_WRITES=NONE'
    0
  end
end

exit AiNotebookRouterAdmission.run if __FILE__ == $PROGRAM_NAME
