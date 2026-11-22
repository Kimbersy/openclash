#!/usr/bin/env ruby
# frozen_string_literal: true
# Only compares active OpenClash source YAML proxy definitions to the actual
# running Mihomo config file. No network, API calls, secrets printed or writes.
# Deliberately DOES NOT establish that Mihomo memory uses identical credentials.
require 'psych'

module AiSourceRuntimeDefinitionsReadOnly
  module_function
  CORE_ROOT = '/etc/openclash/core/'
  SOURCE_ROOT = '/etc/openclash/config/'
  MAX_CONFIG_BYTES = 20_000_000
  MAX_LEAVES = 5000

  def flag(argv, key)
    at = argv.index(key)
    return argv[at + 1] if at && at + 1 < argv.size
    argv.find { |v| v.start_with?(key + '=') }&.split('=', 2)&.last
  end

  def one_running_core
    matches = []
    Dir['/proc/[0-9]*/cmdline'].each do |file|
      begin
        pid = file.split('/')[2]
        next unless File.readlink("/proc/#{pid}/exe").start_with?(CORE_ROOT)
        argv = File.binread(file).split("\0")
        next if argv.any? { |x| %w[/tmp/openclash-ai- /tmp/openclash-probe- /tmp/oc-ai-].any? { |p| x.include?(p) } }
        cwd = File.readlink("/proc/#{pid}/cwd")
        home = File.expand_path(flag(argv, '-d') || cwd, cwd)
        cfg = File.expand_path(flag(argv, '-f') || 'config.yaml', home)
        next unless File.file?(cfg) && File.size(cfg).between?(1, MAX_CONFIG_BYTES)
        matches << [pid, cfg]
      rescue StandardError
        next
      end
    end
    matches.size == 1 ? matches[0] : nil
  end

  def proc_starttime(stat)
    return nil unless stat.is_a?(String)
    last = stat.rindex(')')
    return nil unless last
    fields = stat[(last + 1)..-1].split
    value = fields[19] # Linux /proc/PID/stat field 22
    value if value && value.match?(/\A\d+\z/)
  end

  def core_identity(pid)
    exe = File.readlink("/proc/#{pid}/exe")
    return nil unless exe.start_with?(CORE_ROOT)
    st = proc_starttime(File.binread("/proc/#{pid}/stat",8192))
    return nil unless st
    [exe,File.readlink("/proc/#{pid}/ns/net"),st]
  rescue StandardError
    nil
  end

  def uci_selected_source
    value = IO.popen(['uci','-q','get','openclash.config.config_path'], err: File::NULL) do |io|
      io.read(2048)
    end
    value = value.to_s.strip
    return nil if value.empty? || value.bytesize > 1024 || value.match?(/[\x00-\x1f\x7f]/)
    selected = File.expand_path(value.start_with?('/') ? value : File.join(SOURCE_ROOT,value))
    return nil unless selected.start_with?(SOURCE_ROOT)
    resolved = File.realpath(selected)
    return nil unless resolved.start_with?(SOURCE_ROOT) && File.file?(resolved) &&
      File.size(resolved).between?(1,MAX_CONFIG_BYTES)
    resolved
  rescue StandardError
    nil
  end

  def stable_read(path)
    first = File.stat(path)
    return nil unless first.file? && first.size.between?(1,MAX_CONFIG_BYTES)
    bytes = File.binread(path,MAX_CONFIG_BYTES+1)
    second = File.stat(path)
    fields = ->(s) { [s.dev,s.ino,s.size,s.mtime,s.ctime] }
    return nil unless bytes.bytesize == first.size &&
      fields.call(first) == fields.call(second)
    parsed = Psych.safe_load(bytes,aliases:false)
    parsed if parsed.is_a?(Hash)
  rescue StandardError
    nil
  end

  def leaves_by_name(cfg)
    return nil unless cfg.is_a?(Hash)
    # An embedded-only census cannot claim completeness if proxy-providers
    # have become active since the last real-device snapshot.
    pp = cfg['proxy-providers']
    return nil unless pp.nil? || pp == {}
    leaves = cfg['proxies']
    return nil unless leaves.is_a?(Array) && leaves.length.between?(1,MAX_LEAVES)
    named = {}
    leaves.each do |node|
      return nil unless node.is_a?(Hash) && node['name'].is_a?(String) &&
        !node['name'].empty? && node['name'].bytesize <= 256 &&
        node['type'].is_a?(String) && !node['type'].empty?
      key = node['name']
      return nil if named.key?(key)
      named[key] = node
    end
    named
  end

  def compare(source, running)
    a = leaves_by_name(source)
    b = leaves_by_name(running)
    return [nil,'HOLD_LAYOUT_OR_PROXY_PROVIDER'] unless a && b
    names_a = a.keys
    names_b = b.keys
    present = (names_a & names_b)
    exact = present.count { |key| a[key] == b[key] }
    different = present.length - exact
    missing = (names_a - names_b).length
    extra = (names_b - names_a).length
    metrics = {
      'SOURCE_EMBEDDED_LEAF_COUNT'=>names_a.length,
      'RUNTIME_DISK_LEAF_COUNT'=>names_b.length,
      'COMMON_NAME_COUNT'=>present.length,
      'FULL_DEFINITION_MATCH_COUNT'=>exact,
      'SAME_NAME_DIFFERENT_DEFINITION_COUNT'=>different,
      'SOURCE_ONLY_COUNT'=>missing,
      'RUNTIME_ONLY_COUNT'=>extra,
      'ORDER_ONLY_CHANGE'=>(exact==names_a.length && missing==0 && extra==0 && names_a!=names_b ? 'YES' : 'NO')
    }
    status = if different==0 && missing==0 && extra==0
      'SOURCE_RUNTIME_DISK_FULL_DEFINITIONS_MATCH'
    else
      'HOLD_SOURCE_RUNTIME_DEFINITION_DIFFERENCE'
    end
    [metrics,status]
  end

  def run
    puts 'SOURCE_RUNTIME_DEFINITIONS=START READ_ONLY_NO_HTTP=YES'
    core = one_running_core
    unless core
      puts 'SOURCE_RUNTIME_RESULT=HOLD_CORE_NOT_UNIQUE'
      return
    end
    pid, running_path = core
    original_identity = core_identity(pid)
    unless original_identity
      puts 'SOURCE_RUNTIME_RESULT=HOLD_CORE_IDENTITY_UNKNOWN'
      return
    end
    source_path = uci_selected_source
    unless source_path
      puts 'SOURCE_RUNTIME_RESULT=HOLD_SELECTED_SOURCE_UNAVAILABLE'
      return
    end
    src = stable_read(source_path)
    cfg = stable_read(running_path)
    unless src && cfg
      puts 'SOURCE_RUNTIME_RESULT=HOLD_DISK_READ_OR_CHANGE'
      return
    end
    unless original_identity == core_identity(pid) &&
      File.realpath(running_path) == File.realpath(one_running_core&.last.to_s)
      puts 'SOURCE_RUNTIME_RESULT=HOLD_CORE_CHANGED'
      return
    end
    metrics,status = compare(src,cfg)
    puts "SOURCE_RUNTIME_RESULT=#{status}"
    metrics&.each { |k,v| puts "#{k}=#{v}" }
    puts 'SOURCE_AND_RUNTIME_PATHS=NOT_EMITTED'
    puts 'NODE_NAMES_AND_CONNECTION_PARAMETERS=NOT_EMITTED'
    puts 'MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED'
    puts 'ENABLED_SUBSCRIPTION_MERGE_PROVENANCE=NOT_VERIFIED'
    puts 'REMOTE_UPDATE_SUCCESS=NOT_VERIFIED AI_BUSINESS=UNKNOWN'
  rescue StandardError
    puts 'SOURCE_RUNTIME_RESULT=HOLD_RUNTIME'
  ensure
    puts 'PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  end
end

AiSourceRuntimeDefinitionsReadOnly.run if __FILE__ == $PROGRAM_NAME
