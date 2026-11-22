#!/usr/bin/env ruby
# frozen_string_literal: true
# Anonymous size/format profiling of ALL cached rule providers.
# No cache CONTENT reads, no Mihomo or network calls, no source changes.
# A >1MiB YAML file is only a SIZE_CLASSIFIED item, never YAML validated.
# Runtime dependency: psych only (confirmed on real iStoreOS).
require 'psych'

module AiRuleCacheSizeProfile
  module_function
  CORE_ROOT = '/etc/openclash/core/'
  MAX_CONFIG = 20_000_000
  MAX_FILE = 8 * 1024 * 1024
  MAX_TOTAL = 48 * 1024 * 1024
  MAX_PROVIDERS = 2000
  SMALL_YAML = 1024 * 1024

  def active_source
    hits = []
    Dir['/proc/[0-9]*/cmdline'].each do |file|
      begin
        pid = file.split('/')[2]
        next unless File.readlink("/proc/#{pid}/exe").start_with?(CORE_ROOT)
        args = File.binread(file).split("\0")
        next if args.any? { |arg| %w[/tmp/openclash-ai- /tmp/openclash-probe- /tmp/oc-ai-].any? { |x| arg.include?(x) } }
        cwd = File.readlink("/proc/#{pid}/cwd")
        fi = args.index('-f')
        di = args.index('-d')
        conf = (fi && args[fi + 1]) || args.find { |x| x.start_with?('-f=') }&.split('=', 2)&.last
        home = (di && args[di + 1]) || args.find { |x| x.start_with?('-d=') }&.split('=', 2)&.last
        root = File.expand_path(home || cwd, cwd)
        path = File.expand_path(conf || 'config.yaml', root)
        next unless File.file?(path) && File.size(path).between?(1, MAX_CONFIG)
        hits << [path, root]
      rescue StandardError
        next
      end
    end
    hits.length == 1 ? hits.first : nil
  end

  def hold(code)
    [code, nil]
  end

  def profile(cfg, home)
    return hold('HOLD_CONFIG_LAYOUT') unless cfg.is_a?(Hash) && home.is_a?(String)
    return hold('HOLD_GEO_STATE_CHANGED') if cfg['geodata-mode'] == true ||
      cfg['geo-auto-update'] == true || !cfg.key?('geox-url')
    providers = cfg['rule-providers']
    return hold('HOLD_PROVIDER_LAYOUT') unless providers.is_a?(Hash) &&
      providers.length.between?(1, MAX_PROVIDERS)
    # Keep this a classification of the verified 20-source device snapshot;
    # future subscription changes get a fresh matching source witness.
    return hold('HOLD_SOURCE_COUNT_CHANGED') unless providers.length == 20
    root = File.realpath(home)
    return hold('HOLD_HOME_NOT_DIRECTORY') unless File.directory?(root)
    c = {
      'FORMAT_YAML' => 0, 'FORMAT_TEXT' => 0, 'FORMAT_MRS' => 0,
      'YAML_LE_1M' => 0, 'YAML_GT_1M' => 0,
      'ALL_LE_1M' => 0, 'ALL_GT_1M' => 0,
      'ALL_GT_4M' => 0
    }
    total = 0
    seen = {}
    providers.each do |name, item|
      return hold('HOLD_PROVIDER_LAYOUT') unless name.is_a?(String) &&
        item.is_a?(Hash) && item['type'] == 'http' && !item.key?('path-in-bundle')
      fmt = item.fetch('format', 'yaml')
      behavior = item['behavior']
      return hold('HOLD_PROVIDER_FORMAT') unless %w[yaml text mrs].include?(fmt) &&
        %w[domain ipcidr classical].include?(behavior) &&
        !(fmt == 'mrs' && behavior == 'classical')
      path = item['path']
      return hold('HOLD_PATH') unless path.is_a?(String) && !path.empty? &&
        !path.include?("\0") && !path.split('/').include?('..')
      full = File.expand_path(path, root)
      return hold('HOLD_PATH') unless full.start_with?(root + '/') &&
        File.realpath(full) == full && !File.symlink?(full)
      return hold('HOLD_DUPLICATE_PATH') if seen[full]
      seen[full] = true
      st = File.lstat(full)
      return hold('HOLD_FILE') unless st.file? && st.size.between?(1, MAX_FILE)
      total += st.size
      return hold('HOLD_TOTAL_BUDGET') if total > MAX_TOTAL
      c["FORMAT_#{fmt.upcase}"] += 1
      c[st.size <= SMALL_YAML ? 'ALL_LE_1M' : 'ALL_GT_1M'] += 1
      c['ALL_GT_4M'] += 1 if st.size > 4 * 1024 * 1024
      c[st.size <= SMALL_YAML ? 'YAML_LE_1M' : 'YAML_GT_1M'] += 1 if fmt == 'yaml'
    end
    ['SIZE_FORMAT_CLASSIFIED', c]
  rescue SystemCallError, ArgumentError
    hold('HOLD_FILESYSTEM')
  rescue StandardError
    hold('HOLD_PROFILE_RUNTIME')
  end

  def run
    puts 'RULE_CACHE_SIZE_PROFILE=START READ_ONLY=YES'
    located = active_source
    unless located
      puts 'PROFILE_RESULT=HOLD_CORE_NOT_UNIQUE'
      puts 'PRODUCTION_CONFIG=UNCHANGED CACHE_CONTENT=NOT_READ AUTO_SWITCH=OFF'
      return
    end
    file, home = located
    bytes = File.binread(file, MAX_CONFIG + 1)
    unless bytes.bytesize.between?(1, MAX_CONFIG)
      puts 'PROFILE_RESULT=HOLD_CONFIG_SIZE'
      return
    end
    cfg = Psych.safe_load(bytes, aliases: false)
    status, counts = profile(cfg, home)
    puts "PROFILE_RESULT=#{status}"
    if counts
      counts.each { |key, value| puts "#{key}=#{value}" }
      puts "PROVIDER_COUNT=#{counts['FORMAT_YAML'] + counts['FORMAT_TEXT'] + counts['FORMAT_MRS']}"
    end
    puts 'YAML_LARGE_SEMANTICS=UNPARSED'
    puts 'MIHOMO_SYNTAX=NOT_VALIDATED NETWORK_ISOLATION=NOT_PROVEN'
    puts 'PRODUCTION_CONFIG=UNCHANGED CACHE_CONTENT=NOT_READ LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  rescue StandardError
    puts 'PROFILE_RESULT=HOLD_READ_ONLY_RUNTIME'
    puts 'PRODUCTION_CONFIG=UNCHANGED CACHE_CONTENT=NOT_READ AUTO_SWITCH=OFF'
  end
end

AiRuleCacheSizeProfile.run if __FILE__ == $PROGRAM_NAME
