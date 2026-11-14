#!/usr/bin/env ruby
# frozen_string_literal: true
# Read-only STATIC local cache structure inspection; no Mihomo invocation.
# Does NOT prove Mihomo syntax, loaded runtime rules, or lack of network
# access by any future parser. Never prints cache text, names, URLs or paths.
# Only psych (confirmed on the user's minimal iStoreOS Ruby).
require 'psych'

module AiRuleCacheStructureReadOnly
  module_function

  CORE_ROOT = '/etc/openclash/core/'
  MAX_CONFIG = 20_000_000
  MAX_FILE = 8 * 1024 * 1024
  MAX_TOTAL = 48 * 1024 * 1024
  MAX_PROVIDERS = 2000
  MAX_PAYLOAD = 250_000

  def active_source
    matches = []
    Dir['/proc/[0-9]*/cmdline'].each do |file|
      begin
        pid = file.split('/')[2]
        next unless File.readlink("/proc/#{pid}/exe").start_with?(CORE_ROOT)
        argv = File.binread(file).split("\0")
        next if argv.any? { |a| %w[/tmp/openclash-ai- /tmp/openclash-probe- /tmp/oc-ai-].any? { |p| a.include?(p) } }
        cwd = File.readlink("/proc/#{pid}/cwd")
        fi = argv.index('-f')
        di = argv.index('-d')
        path = (fi && argv[fi + 1]) || argv.find { |a| a.start_with?('-f=') }&.split('=', 2)&.last
        home = (di && argv[di + 1]) || argv.find { |a| a.start_with?('-d=') }&.split('=', 2)&.last
        root = File.expand_path(home || cwd, cwd)
        config = File.expand_path(path || 'config.yaml', root)
        next unless File.file?(config) && File.size(config).between?(1, MAX_CONFIG)
        matches << [config, root]
      rescue StandardError
        next
      end
    end
    matches.size == 1 ? matches.first : nil
  end

  def same_stat?(a, b)
    a.dev == b.dev && a.ino == b.ino && a.size == b.size &&
      a.mtime == b.mtime && a.ctime == b.ctime
  end

  def file_shape(path, fmt, behavior)
    return 'HOLD_FILE_FORMAT' unless %w[yaml text mrs].include?(fmt)
    return 'HOLD_BEHAVIOR' unless %w[domain ipcidr classical].include?(behavior)
    return 'HOLD_MRS_BEHAVIOR' if fmt == 'mrs' && behavior == 'classical'
    return 'MRS_UNPARSED' if fmt == 'mrs'

    flags = File::RDONLY | (File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0)
    File.open(path, flags) do |f|
      st = f.stat
      return 'HOLD_FILE_CHANGED' unless st.file? && st.size.between?(1, MAX_FILE)
      bytes = f.read(MAX_FILE + 1)
      return 'HOLD_FILE_SIZE' unless bytes.bytesize == st.size
      return 'HOLD_FILE_CHANGED' unless same_stat?(st, f.stat)
      return 'HOLD_FILE_ENCODING' unless bytes.force_encoding('UTF-8').valid_encoding? &&
        !bytes.include?("\0")
      if fmt == 'yaml'
        yaml = Psych.safe_load(bytes, aliases: false)
        return 'HOLD_YAML_LAYOUT' unless yaml.is_a?(Hash) &&
          yaml['payload'].is_a?(Array) && yaml['payload'].size.between?(1, MAX_PAYLOAD) &&
          yaml['payload'].all? { |v| v.is_a?(String) && !v.strip.empty? }
      else
        lines = bytes.each_line.count { |v| !v.strip.empty? && !v.lstrip.start_with?('#') }
        return 'HOLD_TEXT_LAYOUT' unless lines.between?(1, MAX_PAYLOAD)
      end
      return 'HOLD_FILE_CHANGED' unless same_stat?(st, File.lstat(path))
    end
    'STATIC_STRUCTURE_PASS'
  rescue Psych::Exception
    'HOLD_YAML_PARSE'
  rescue StandardError
    'HOLD_FILE_ACCESS_OR_RUNTIME'
  end

  def classify(config, home)
    counts = { 'YAML' => 0, 'TEXT' => 0, 'MRS_UNPARSED' => 0 }
    hold = lambda { |code| [code, counts] }
    return hold.call('HOLD_CONFIG_LAYOUT') unless config.is_a?(Hash) && home.is_a?(String)
    # Must not silently change the geo facts collected at 17:06.
    return hold.call('HOLD_GEO_STATE_CHANGED') if config['geodata-mode'] == true ||
      config['geo-auto-update'] == true || !config.key?('geox-url')
    providers = config['rule-providers']
    return hold.call('HOLD_PROVIDER_LAYOUT') unless providers.is_a?(Hash) &&
      providers.size.between?(1, MAX_PROVIDERS)
    # Snapshot is 20. A changed catalog requires new provenance, not blind reuse.
    return hold.call('HOLD_PROVIDER_COUNT_CHANGED') unless providers.size == 20
    root = File.realpath(home)
    total = 0
    paths = {}
    providers.each_value do |item|
      return hold.call('HOLD_PROVIDER_LAYOUT') unless item.is_a?(Hash) &&
        item['type'] == 'http' && !item.key?('path-in-bundle')
      path = item['path']
      return hold.call('HOLD_CACHE_PATH') unless path.is_a?(String) && !path.empty? &&
        !path.include?("\0") && !path.split('/').include?('..')
      full = File.expand_path(path, root)
      return hold.call('HOLD_CACHE_PATH') unless full.start_with?(root + '/') &&
        File.realpath(full) == full && !File.symlink?(full) && !paths[full]
      paths[full] = true
      stat = File.lstat(full)
      return hold.call('HOLD_FILE_SIZE') unless stat.file? && stat.size.between?(1, MAX_FILE)
      total += stat.size
      return hold.call('HOLD_TOTAL_BUDGET') if total > MAX_TOTAL
      fmt = item.fetch('format', 'yaml')
      behavior = item['behavior']
      status = file_shape(full, fmt, behavior)
      return hold.call(status) if status.start_with?('HOLD_')
      counts[fmt == 'mrs' ? 'MRS_UNPARSED' : fmt.upcase] += 1
    end
    [counts['MRS_UNPARSED'] > 0 ? 'HOLD_MRS_BINARY_UNPARSED' : 'STATIC_STRUCTURE_PASS', counts]
  rescue StandardError
    hold.call('HOLD_CATALOG_ACCESS_OR_RUNTIME')
  end

  def run
    puts 'RULE_CACHE_STRUCTURE=START READ_ONLY=YES'
    source = active_source
    unless source
      puts 'STRUCTURE_RESULT=HOLD_CORE_NOT_UNIQUE'
      puts 'PRODUCTION_CONFIG=UNCHANGED MIHOMO_TEST=NOT_RUN AUTO_SWITCH=OFF'
      return
    end
    file, home = source
    raw = File.binread(file, MAX_CONFIG + 1)
    return puts('STRUCTURE_RESULT=HOLD_CONFIG_SIZE') unless raw.bytesize.between?(1, MAX_CONFIG)
    config = Psych.safe_load(raw, aliases: false)
    result, counts = classify(config, home)
    puts "STRUCTURE_RESULT=#{result}"
    puts "CACHE_YAML_STATIC=#{counts['YAML']}"
    puts "CACHE_TEXT_STATIC=#{counts['TEXT']}"
    puts "CACHE_MRS_UNPARSED=#{counts['MRS_UNPARSED']}"
    puts 'MIHOMO_SYNTAX=NOT_VALIDATED NETWORK_ISOLATION=NOT_PROVEN'
    puts 'PRODUCTION_CONFIG=UNCHANGED RULE_CACHES=READ_ONLY LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  rescue StandardError
    puts 'STRUCTURE_RESULT=HOLD_READ_ONLY_RUNTIME'
    puts 'PRODUCTION_CONFIG=UNCHANGED MIHOMO_TEST=NOT_RUN AUTO_SWITCH=OFF'
  end
end

AiRuleCacheStructureReadOnly.run if __FILE__ == $PROGRAM_NAME
