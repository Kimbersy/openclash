#!/usr/bin/env ruby
# frozen_string_literal: true
# iStoreOS-only read-only, ANONYMOUS rule-provider dependency inventory.
# Device receipt 2026-11-14: prior real-config overlay HOLD_RULE_PROVIDERS.
# Does not fetch, open, hash, copy, edit, print source/paths/URLs/rule content,
# start Mihomo test, switch proxy, use a browser, or install anything.
# Only Ruby psych (real iStoreOS already confirmed). No optional stdlib.
require 'psych'

module AiRuleProviderInventory
  module_function
  ROOT = '/etc/openclash/core/'
  MAX_BYTES = 20_000_000
  MAX_PROVIDERS = 2000

  def active_config
    matches=[]
    Dir['/proc/[0-9]*/cmdline'].each do |file|
      begin
        pid=file.split('/')[2]
        next unless File.readlink("/proc/#{pid}/exe").start_with?(ROOT)
        args=File.binread(file).split("\0")
        next if args.any? { |x| %w[/tmp/openclash-ai- /tmp/openclash-probe- /tmp/oc-ai-].any? { |m| x.include?(m) } }
        cwd=File.readlink("/proc/#{pid}/cwd")
        fi=args.index('-f'); di=args.index('-d')
        cf=(fi && args[fi+1]) || args.find { |x| x.start_with?('-f=') }&.split('=',2)&.last
        dr=(di && args[di+1]) || args.find { |x| x.start_with?('-d=') }&.split('=',2)&.last
        home=File.expand_path(dr || cwd,cwd)
        path=File.expand_path(cf || 'config.yaml',home)
        next unless File.file?(path) && File.size(path).between?(1,MAX_BYTES)
        matches << [path,home]
      rescue StandardError
        next
      end
    end
    matches.size==1 ? matches.first : nil
  end

  def cache_status(value, home)
    return 'no_explicit_path' unless value.is_a?(String) && !value.empty?
    return 'unsafe_path' if value.include?("\0")
    # A rule-provider path can default to the MD5 of the HTTP URL.
    # Do not touch URLs to derive that cache location here.
    expanded=File.expand_path(value,home)
    allowed=File.realpath(home)
    return 'outside_home' unless expanded.start_with?(allowed + '/')
    return 'missing' unless File.exist?(expanded) || File.symlink?(expanded)
    # Never read a provider file. Realpath checks the entire path's parents.
    return 'unsafe_path' if File.symlink?(expanded)
    real=File.realpath(expanded)
    return 'outside_home' unless real.start_with?(allowed + '/')
    return 'unsafe_path' unless File.file?(expanded)
    return 'unsafe_path' unless File.size(expanded).between?(1,15_000_000)
    'local_regular'
  rescue ArgumentError, SystemCallError
    'unverified'
  end

  def classify(config, home)
    return [nil,'HOLD_CONFIG_LAYOUT'] unless config.is_a?(Hash) && home.is_a?(String)
    map=config['rule-providers']
    return [nil,'HOLD_PROVIDER_LAYOUT'] unless map.is_a?(Hash) && !map.empty? && map.length<=MAX_PROVIDERS
    counts=Hash.new(0)
    map.each do |name, item|
      return [nil,'HOLD_PROVIDER_LAYOUT'] unless name.is_a?(String) && item.is_a?(Hash)
      type=item['type']
      category=%w[http file inline].include?(type) ? type : 'unknown'
      counts["type_#{category}"]+=1
      if category=='inline'
        counts[item['payload'].is_a?(Array) ? 'inline_payload_present' : 'inline_payload_unknown']+=1
      else
        counts["cache_#{cache_status(item['path'],home)}"]+=1
      end
      counts['bundle_dependency']+=1 if item.key?('path-in-bundle')
    end
    rules=config['rules']
    return [nil,'HOLD_RULES_LAYOUT'] unless rules.is_a?(Array) && rules.all? { |x| x.is_a?(String) }
    counts['ruleset_reference_present']=1 if rules.any? { |s| s.match?(/(?:\A|[,(])RULE-SET,/i) }
    counts['geo_reference_present']=1 if rules.any? { |s| s.match?(/(?:\A|[,(])(?:GEOIP|GEOSITE),/i) }
    counts['geo_mode_enabled']=1 if config['geodata-mode']==true || config['geo-auto-update']==true || config.key?('geox-url')
    counts['proxy_providers_present']=1 if config.key?('proxy-providers') && config['proxy-providers']!={}
    counts['group_provider_use_present']=1 if config['proxy-groups'].is_a?(Array) &&
      config['proxy-groups'].any? { |g| g.is_a?(Hash) && (g.key?('use') || g['include-all']==true) }
    [counts,'RULE_PROVIDER_SHAPE_CLASSIFIED']
  rescue StandardError
    [nil,'HOLD_INVENTORY_RUNTIME']
  end

  OUTPUT_KEYS=%w[
    type_http type_file type_inline type_unknown
    cache_local_regular cache_missing cache_no_explicit_path
    cache_outside_home cache_unsafe_path cache_unverified
    inline_payload_present inline_payload_unknown bundle_dependency
    ruleset_reference_present geo_reference_present geo_mode_enabled
    proxy_providers_present group_provider_use_present
  ].freeze

  def run
    puts 'RULE_PROVIDER_INVENTORY=START READ_ONLY=YES'
    loc=active_config
    unless loc
      puts 'INVENTORY_RESULT=HOLD_CORE_NOT_UNIQUE'
      puts 'PRODUCTION_CONFIG=UNCHANGED AI_AUTO_SWITCH=OFF'
      return
    end
    file,home=loc
    bytes=File.binread(file,MAX_BYTES+1)
    return puts('INVENTORY_RESULT=HOLD_CONFIG_SIZE PRODUCTION_CONFIG=UNCHANGED') unless bytes.bytesize.between?(1,MAX_BYTES)
    config=Psych.safe_load(bytes,aliases:false)
    data,verdict=classify(config,home)
    puts "INVENTORY_RESULT=#{verdict}"
    if data
      puts "RULE_PROVIDER_TOTAL=#{data.fetch('type_http',0)+data.fetch('type_file',0)+data.fetch('type_inline',0)+data.fetch('type_unknown',0)}"
      OUTPUT_KEYS.each { |k| puts "#{k.upcase}=#{data.fetch(k,0)}" }
    end
    puts 'PRIVATE_COPY_TEST=NOT_RUN RULE_CONTENT=NOT_READ'
    puts 'PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AI_AUTO_SWITCH=OFF'
  rescue StandardError
    puts 'INVENTORY_RESULT=HOLD_READ_ONLY_RUNTIME'
    puts 'PRODUCTION_CONFIG=UNCHANGED AI_AUTO_SWITCH=OFF'
  end
end

AiRuleProviderInventory.run if __FILE__==$PROGRAM_NAME
