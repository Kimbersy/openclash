#!/usr/bin/env ruby
# frozen_string_literal: true
# Safe, no-write inventory of configured nodes and runtime provider entries.
# Never prints subscription URLs, proxy names, addresses, credentials or controller secret.
require 'psych'
require 'json'
require 'open3'
module AiSubscriptionInventory
  module_function

  def classify(cfg, loaded_providers = nil, uci = '')
    raise 'not_mapping' unless cfg.is_a?(Hash)
    direct = cfg['proxies'].is_a?(Array) ? cfg['proxies'] : []
    declared = cfg['proxy-providers'].is_a?(Hash) ? cfg['proxy-providers'] : {}
    names = direct.filter_map { |p| p['name'] if p.is_a?(Hash) && p['name'].is_a?(String) }
    # Official Mihomo GET /providers/proxies wraps entries under 'providers'.
    # Reject unknown envelope shapes rather than claiming a complete inventory.
    provider_map = if declared.empty?
      {}
    elsif loaded_providers.is_a?(Hash) && loaded_providers['providers'].is_a?(Hash)
      loaded_providers['providers']
    else
      nil
    end
    providers_loaded = 0
    provider_status = provider_map.nil? ? 'UNVERIFIED' : 'READABLE'
    if provider_map
      declared.keys.each do |key|
        entry = provider_map[key]
        unless entry.is_a?(Hash) && entry['proxies'].is_a?(Array)
          provider_status = 'PARTIAL'
          next
        end
        provider_nodes = entry['proxies'].filter_map { |p| p['name'] if p.is_a?(Hash) && p['name'].is_a?(String) }
        names.concat(provider_nodes)
        providers_loaded += provider_nodes.length
      end
    end
    sub_ids = uci.scan(/^openclash\.([^.=]+)=config_subscribe\s*$/).flatten.uniq
    enabled = sub_ids.count do |id|
      uci.match?(/^openclash\.#{Regexp.escape(id)}\.(?:enabled|enable)='?1'?\s*$/)
    end
    disabled = sub_ids.count do |id|
      uci.match?(/^openclash\.#{Regexp.escape(id)}\.(?:enabled|enable)='?0'?\s*$/)
    end
    {
      embedded: direct.length,
      provider_definitions: declared.length,
      provider_nodes_loaded: providers_loaded,
      provider_status: provider_status,
      unique_names: names.uniq.length,
      name_conflicts: names.length - names.uniq.length,
      subscribe_sections: sub_ids.length,
      subscribe_flag_enabled: enabled,
      subscribe_flag_unknown: sub_ids.length - enabled - disabled,
      source_coverage: 'UNVERIFIED_NEEDS_MERGE_PROVENANCE'
    }
  end

  def process
    runtime = nil
    Dir.glob('/proc/[0-9]*/cmdline').each do |cp|
      begin
        pid = cp.split('/')[2]
        exe = File.readlink("/proc/#{pid}/exe")
        next unless exe.start_with?('/etc/openclash/core/') || File.basename(exe).match?(/\A(?:clash_meta|mihomo)\z/)
        argv = File.binread(cp).split("\0")
        next if argv.any? { |x| x.include?('/tmp/openclash-probe-') }
        cwd = File.readlink("/proc/#{pid}/cwd")
        flag = lambda do |name|
          i = argv.index(name)
          i ? argv[i + 1] : argv.find { |a| a.start_with?(name + '=') }&.split('=', 2)&.last
        end
        home = File.expand_path(flag.call('-d') || flag.call('--dir') || cwd, cwd)
        conf = File.expand_path(flag.call('-f') || flag.call('--config') || 'config.yaml', home)
        next unless File.file?(conf) && File.size(conf).between?(1, 20_000_000)
        runtime = [pid, argv, conf, flag]
        break
      rescue StandardError
        next
      end
    end
    return puts('INVENTORY=BLOCKED REASON=NO_RUNTIME_CONFIG') unless runtime
    pid, _argv, config_path, flag = runtime
    cfg = Psych.safe_load(File.binread(config_path), aliases: false)
    output, = Open3.capture2('uci', '-q', 'show', 'openclash', err: File::NULL)
    declared = cfg['proxy-providers'].is_a?(Hash) ? cfg['proxy-providers'] : {}
    loaded = declared.empty? ? {} : nil
    if !declared.empty?
      address = (flag.call('-ext-ctl') || cfg['external-controller']).to_s
      secret = (flag.call('-secret') || cfg['secret']).to_s
      match = /\A(?:127\.0\.0\.1|0\.0\.0\.0):([0-9]{1,5})\z/.match(address)
      if match && match[1].to_i.between?(1, 65535) && !secret.empty? && secret.bytesize <= 512 && !secret.match?(/[\x00-\x1f]/)
        port = match[1].to_i
        inodes = %w[/proc/net/tcp /proc/net/tcp6].flat_map do |p|
          next [] unless File.file?(p)
          File.readlines(p).drop(1).filter_map do |line|
            cols = line.split
            cols[9] if cols.size > 9 && cols[3] == '0A' && cols[1].split(':').last.to_i(16) == port
          end
        end
        owned = Dir.glob("/proc/#{pid}/fd/*").any? do |fd|
          begin
            inodes.include?(File.readlink(fd)[/\Asocket:\[(\d+)\]\z/, 1])
          rescue StandardError
            false
          end
        end
        if owned
          begin
            args = ['curl', '-q', '--noproxy', '*', '--silent', '--fail', '--connect-timeout', '2', '--max-time', '7', '--config', '-', "http://127.0.0.1:#{port}/providers/proxies"]
            payload = ''
            IO.popen(args, 'r+', err: File::NULL) do |io|
              escaped = secret.gsub(/[\\"]/){ |c| '\\' + c }
              io.write("header = \"Authorization: Bearer #{escaped}\"\n")
              io.close_write
              payload = io.read(2_000_001)
            end
            loaded = JSON.parse(payload) if payload.bytesize.between?(1, 2_000_000)
          rescue StandardError
            loaded = nil
          end
        end
      end
    end
    result = classify(cfg, loaded, output)
    puts "INVENTORY=PASS EMBEDDED=#{result[:embedded]} PROVIDERS_DECLARED=#{result[:provider_definitions]} PROVIDER_LOADED=#{result[:provider_nodes_loaded]} PROVIDER_STATUS=#{result[:provider_status]}"
    puts "UNIQUE_NODE_NAMES=#{result[:unique_names]} NAME_CONFLICTS=#{result[:name_conflicts]}"
    puts "SUBSCRIPTION_SECTIONS=#{result[:subscribe_sections]} FLAG_ENABLED=#{result[:subscribe_flag_enabled]} FLAG_UNKNOWN=#{result[:subscribe_flag_unknown]}"
    puts "SOURCE_COVERAGE=#{result[:source_coverage]}"
  rescue StandardError
    puts 'INVENTORY=UNAVAILABLE_NO_PRIVATE_OUTPUT'
  end
end
AiSubscriptionInventory.process if $PROGRAM_NAME == __FILE__
