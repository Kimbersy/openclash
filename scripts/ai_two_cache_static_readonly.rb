#!/usr/bin/env ruby
# frozen_string_literal: true
# Anonymous targeted structural check: one YAML (>1 MiB), one MRS header.
# Only Psych: verified installed on minimal iStoreOS. No network or core invocations.
require 'psych'

module AiTwoCacheStatic
  module_function
  CORE_ROOT = '/etc/openclash/core/'
  MAX_CONFIG = 20_000_000
  MAX_EACH = 8 * 1024 * 1024
  MAX_TOTAL = 48 * 1024 * 1024
  ONE_MIB = 1024 * 1024
  FOUR_MIB = 4 * ONE_MIB
  LINE_CAP = 16 * 1024
  MAX_ITEMS = 250_000
  MRS_V1_MAGIC = "MRS\x01".b.freeze

  def locate
    found = []
    Dir['/proc/[0-9]*/cmdline'].each do |cmd|
      begin
        pid = cmd.split('/')[2]
        next unless File.readlink("/proc/#{pid}/exe").start_with?(CORE_ROOT)
        argv = File.binread(cmd).split("\0")
        next if argv.any? { |a| %w[/tmp/openclash-ai- /tmp/openclash-probe- /tmp/oc-ai-].any? { |x| a.include?(x) } }
        cwd = File.readlink("/proc/#{pid}/cwd")
        fi, di = argv.index('-f'), argv.index('-d')
        cf = (fi && argv[fi+1]) || argv.find { |x| x.start_with?('-f=') }&.split('=',2)&.last
        dr = (di && argv[di+1]) || argv.find { |x| x.start_with?('-d=') }&.split('=',2)&.last
        home = File.expand_path(dr || cwd,cwd)
        source = File.expand_path(cf || 'config.yaml',home)
        next unless File.file?(source) && File.size(source).between?(1,MAX_CONFIG)
        found << [source,home]
      rescue StandardError
        next
      end
    end
    found.length==1 ? found.first : nil
  end

  def same_stat?(a,b)
    a.dev==b.dev && a.ino==b.ino && a.size==b.size && a.mtime==b.mtime && a.ctime==b.ctime
  end

  def plan(cfg,home)
    return [nil,'HOLD_CONFIG_LAYOUT'] unless cfg.is_a?(Hash) && home.is_a?(String)
    return [nil,'HOLD_GEO_STATE_CHANGED'] if cfg['geodata-mode']==true || cfg['geo-auto-update']==true || !cfg.key?('geox-url')
    providers=cfg['rule-providers']
    return [nil,'HOLD_PROVIDER_COUNT_CHANGED'] unless providers.is_a?(Hash) && providers.length==20
    root=File.realpath(home)
    return [nil,'HOLD_HOME'] unless File.directory?(root)
    chosen={}
    seen={}
    counts={'yaml_small'=>0,'yaml_big'=>0,'mrs'=>0,'other'=>0}
    total=0
    providers.each do |name,item|
      return [nil,'HOLD_PROVIDER_LAYOUT'] unless name.is_a?(String) && item.is_a?(Hash) && item['type']=='http' && !item.key?('path-in-bundle')
      fmt=item.fetch('format','yaml')
      behavior=item['behavior']
      return [nil,'HOLD_FORMAT_BEHAVIOR'] unless %w[yaml text mrs].include?(fmt) && %w[domain ipcidr classical].include?(behavior) && !(fmt=='mrs' && behavior=='classical')
      path=item['path']
      return [nil,'HOLD_PATH'] unless path.is_a?(String) && !path.empty? && !path.include?("\0") && !path.split('/').include?('..')
      full=File.expand_path(path,root)
      return [nil,'HOLD_PATH'] unless full.start_with?(root+'/') && File.realpath(full)==full && !File.symlink?(full)
      return [nil,'HOLD_PATH_DUPLICATE'] if seen[full]
      seen[full]=true
      st=File.lstat(full)
      return [nil,'HOLD_FILE_LAYOUT'] unless st.file? && st.size.between?(1,MAX_EACH)
      total+=st.size
      return [nil,'HOLD_TOTAL_BUDGET'] if total>MAX_TOTAL
      if fmt=='yaml'
        if st.size>ONE_MIB
          counts['yaml_big']+=1
          return [nil,'HOLD_YAML_SIZE'] if st.size>FOUR_MIB
          chosen[:yaml]=[full,st]
        else
          counts['yaml_small']+=1
        end
      elsif fmt=='mrs'
        counts['mrs']+=1
        return [nil,'HOLD_MRS_SIZE'] if st.size>ONE_MIB
        chosen[:mrs]=[full,st]
      else
        counts['other']+=1
      end
    end
    return [nil,'HOLD_SNAPSHOT_LAYOUT'] unless counts=={'yaml_small'=>18,'yaml_big'=>1,'mrs'=>1,'other'=>0}
    [chosen,'TARGETS_IDENTIFIED']
  rescue StandardError
    [nil,'HOLD_SNAPSHOT_ACCESS']
  end

  def with_safe_file(path,expected)
    return 'HOLD_FILE_CHANGED' unless File.realpath(path)==path && !File.symlink?(path) && same_stat?(File.lstat(path),expected)
    flags=File::RDONLY | (File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0)
    File.open(path,flags) do |f|
      return 'HOLD_FILE_CHANGED' unless same_stat?(f.stat,expected)
      result=yield f
      return 'HOLD_FILE_CHANGED' unless same_stat?(f.stat,expected) && same_stat?(File.lstat(path),expected)
      result
    end
  rescue StandardError
    'HOLD_FILE_ACCESS'
  end

  def inspect_yaml(path,expected)
    with_safe_file(path,expected) do |f|
      header=false
      items=0
      lines=0
      while (line=f.gets(LINE_CAP+1))
        lines+=1
        return 'HOLD_YAML_LINE_TOO_LONG' if line.bytesize>LINE_CAP || (!line.end_with?("\n") && !f.eof?)
        line.force_encoding('UTF-8')
        return 'HOLD_YAML_ENCODING' unless line.valid_encoding? && !line.include?("\0")
        stripped=line.strip
        next if stripped.empty? || stripped.start_with?('#')
        if !header
          return 'HOLD_YAML_LAYOUT' unless line.match?(/\Apayload:\s*(?:\#.*)?\r?\n?\z/)
          header=true
        else
          # Conservative: only flat payload list items, no multiline YAML.
          return 'HOLD_YAML_COMPLEX_LAYOUT' unless line.match?(/\A[ \t]+-[ \t]+\S[^\r\n]*\r?\n?\z/) || line.match?(/\A-[ \t]+\S[^\r\n]*\r?\n?\z/)
          items+=1
          return 'HOLD_YAML_ITEMS_BUDGET' if items>MAX_ITEMS
        end
        return 'HOLD_YAML_LINES_BUDGET' if lines>MAX_ITEMS+50_000
      end
      header && items>0 ? 'YAML_SHALLOW_PASS' : 'HOLD_YAML_EMPTY'
    end
  end

  def inspect_mrs(path,expected)
    with_safe_file(path,expected) do |f|
      f.read(4)==MRS_V1_MAGIC ? 'MRS_V1_MAGIC_MATCH' : 'HOLD_MRS_MAGIC_UNKNOWN'
    end
  end

  def run
    puts 'TARGET_TWO_CACHE=START READ_ONLY=YES'
    active=locate
    unless active
      puts 'TARGET_RESULT=HOLD_CORE_NOT_UNIQUE'
      puts 'PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
      return
    end
    config_path,home=active
    raw=File.binread(config_path,MAX_CONFIG+1)
    return puts('TARGET_RESULT=HOLD_CONFIG_SIZE') unless raw.bytesize.between?(1,MAX_CONFIG)
    config=Psych.safe_load(raw,aliases:false)
    chosen,status=plan(config,home)
    unless chosen
      puts "TARGET_RESULT=#{status}"
      puts 'PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
      return
    end
    yaml=inspect_yaml(*chosen.fetch(:yaml))
    mrs=inspect_mrs(*chosen.fetch(:mrs))
    puts "LARGE_YAML_SHALLOW=#{yaml}"
    puts "MRS_HEADER=#{mrs}"
    puts "TARGET_RESULT=#{yaml=='YAML_SHALLOW_PASS' && mrs=='MRS_V1_MAGIC_MATCH' ? 'LIMITED_STATIC_CHECKS_COMPLETE' : 'HOLD_TARGET_STRUCTURE'}"
    puts 'MRS_BINARY_CONTENT=NOT_PARSED YAML_FULL_SYNTAX=NOT_VALIDATED'
    puts 'MIHOMO_SYNTAX=NOT_VALIDATED NETWORK_ISOLATION=NOT_PROVEN'
    puts 'PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  rescue StandardError
    puts 'TARGET_RESULT=HOLD_READ_ONLY_RUNTIME'
    puts 'PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  end
end

AiTwoCacheStatic.run if __FILE__ == $PROGRAM_NAME
