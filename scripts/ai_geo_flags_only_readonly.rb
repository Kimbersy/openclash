#!/usr/bin/env ruby
# frozen_string_literal: true
# iStoreOS: ONLY distinguish three GEO configuration switches that older
# inventory collapsed as GEO_MODE_ENABLED=1. Zero network and file writes.
# Do not read/print geox-url, provider URLs, nodes, credentials or cache.
# Only runtime dependency is psych, confirmed on user's device.
require 'psych'

module AiGeoFlagOnly
  module_function
  CORE_ROOT = '/etc/openclash/core/'
  MAX = 20_000_000

  def active_source
    matches = []
    Dir['/proc/[0-9]*/cmdline'].each do |file|
      begin
        pid = file.split('/')[2]
        next unless File.readlink("/proc/#{pid}/exe").start_with?(CORE_ROOT)
        argv = File.binread(file).split("\0")
        next if argv.any? { |v| %w[/tmp/openclash-ai- /tmp/openclash-probe- /tmp/oc-ai-].any? { |p| v.include?(p) } }
        cwd = File.readlink("/proc/#{pid}/cwd")
        fi = argv.index('-f')
        di = argv.index('-d')
        path = (fi && argv[fi+1]) || argv.find { |v| v.start_with?('-f=') }&.split('=',2)&.last
        home = (di && argv[di+1]) || argv.find { |v| v.start_with?('-d=') }&.split('=',2)&.last
        config = File.expand_path(path || 'config.yaml',File.expand_path(home || cwd,cwd))
        next unless File.file?(config) && File.size(config).between?(1,MAX)
        matches << config
      rescue StandardError
        next
      end
    end
    matches.size == 1 ? matches.first : nil
  end

  def summary(cfg)
    return nil unless cfg.is_a?(Hash)
    {
      'GEO_DAT_MODE' => cfg['geodata-mode'] == true ? 'TRUE' : cfg.key?('geodata-mode') && cfg['geodata-mode'] != false ? 'UNRECOGNIZED' : 'FALSE',
      'GEO_AUTO_UPDATE' => cfg['geo-auto-update'] == true ? 'TRUE' : cfg.key?('geo-auto-update') && cfg['geo-auto-update'] != false ? 'UNRECOGNIZED' : 'FALSE',
      'GEO_CUSTOM_URL' => cfg.key?('geox-url') ? 'PRESENT' : 'ABSENT',
    }
  end

  def run
    puts 'GEO_FLAGS_ONLY=START READ_ONLY=YES'
    file = active_source
    unless file
      puts 'GEO_RESULT=HOLD_CORE_NOT_UNIQUE'
      puts 'PRODUCTION_CONFIG=UNCHANGED AUTO_SWITCH=OFF'
      return
    end
    raw = File.binread(file,MAX+1)
    unless raw.bytesize.between?(1,MAX)
      puts 'GEO_RESULT=HOLD_CONFIG_SIZE'
      puts 'PRODUCTION_CONFIG=UNCHANGED AUTO_SWITCH=OFF'
      return
    end
    result = summary(Psych.safe_load(raw,aliases:false))
    unless result
      puts 'GEO_RESULT=HOLD_CONFIG_LAYOUT'
      puts 'PRODUCTION_CONFIG=UNCHANGED AUTO_SWITCH=OFF'
      return
    end
    puts 'GEO_RESULT=FLAGS_CLASSIFIED'
    result.each { |k,v| puts "#{k}=#{v}" }
    puts 'RULE_PROVIDER_CACHES=NOT_READ PRIVATE_COPY_TEST=NOT_RUN'
    puts 'PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  rescue StandardError
    puts 'GEO_RESULT=HOLD_READ_ONLY_RUNTIME'
    puts 'PRODUCTION_CONFIG=UNCHANGED AUTO_SWITCH=OFF'
  end
end

AiGeoFlagOnly.run if __FILE__ == $PROGRAM_NAME
