#!/usr/bin/env ruby
# frozen_string_literal: true
# iStoreOS: verify local rule-provider cached bytes using only a temporary,
# private, on-device copy. Never invokes Mihomo -t, providers or the network.
# Never prints configuration, paths, URLs, node names, rules or credentials.
require 'psych'

module AiRuleCacheByteCopyGate
  module_function
  CORE_ROOT = '/etc/openclash/core/'
  MAX_CONFIG = 20_000_000
  MAX_PROVIDERS = 2000
  MAX_FILE = 8 * 1024 * 1024
  MAX_TOTAL = 48 * 1024 * 1024
  CHUNK = 64 * 1024
  PREFIX = 'ai_rule_bytecopy_'

  def active_config
    result = []
    Dir['/proc/[0-9]*/cmdline'].each do |cmd|
      begin
        pid = cmd.split('/')[2]
        next unless File.readlink("/proc/#{pid}/exe").start_with?(CORE_ROOT)
        argv = File.binread(cmd).split("\0")
        next if argv.any? { |s| %w[/tmp/openclash-ai- /tmp/openclash-probe- /tmp/oc-ai-].any? { |t| s.include?(t) } }
        cwd = File.readlink("/proc/#{pid}/cwd")
        fi, di = argv.index('-f'), argv.index('-d')
        name = (fi && argv[fi + 1]) || argv.find { |s| s.start_with?('-f=') }&.split('=', 2)&.last
        home = (di && argv[di + 1]) || argv.find { |s| s.start_with?('-d=') }&.split('=', 2)&.last
        basedir = File.expand_path(home || cwd, cwd)
        source = File.expand_path(name || 'config.yaml', basedir)
        next unless File.file?(source) && File.size(source).between?(1, MAX_CONFIG)
        result << [source, basedir]
      rescue StandardError
        next
      end
    end
    result.size == 1 ? result.first : nil
  end

  def same_file?(a, b)
    a.dev == b.dev && a.ino == b.ino && a.size == b.size &&
      a.mtime == b.mtime && a.ctime == b.ctime
  end

  def catalog(config, home)
    return [nil, 'HOLD_CONFIG_LAYOUT'] unless config.is_a?(Hash) && home.is_a?(String)
    # Real receipt 17:06 was: false / false / custom URL present.
    return [nil, 'HOLD_GEO_STATE_CHANGED'] unless config['geodata-mode'] != true &&
      config['geo-auto-update'] != true && config.key?('geox-url')
    rules = config['rule-providers']
    return [nil, 'HOLD_PROVIDER_LAYOUT'] unless rules.is_a?(Hash) &&
      rules.size.between?(1, MAX_PROVIDERS)
    root = File.realpath(home)
    return [nil, 'HOLD_HOME_DIRECTORY'] unless File.directory?(root)
    total = 0
    sources = []
    seen = {}
    rules.each_value do |entry|
      return [nil, 'HOLD_PROVIDER_LAYOUT'] unless entry.is_a?(Hash) && entry['type'] == 'http'
      return [nil, 'HOLD_PROVIDER_BUNDLE'] if entry.key?('path-in-bundle')
      path = entry['path']
      return [nil, 'HOLD_PROVIDER_PATH'] unless path.is_a?(String) && !path.empty? &&
        !path.include?("\0") && !path.split('/').include?('..')
      expanded = File.expand_path(path, root)
      return [nil, 'HOLD_PROVIDER_PATH'] unless expanded.start_with?(root + '/') &&
        File.realpath(expanded) == expanded && !File.symlink?(expanded)
      return [nil, 'HOLD_DUPLICATE_CACHE'] if seen[expanded]
      seen[expanded] = true
      st = File.lstat(expanded)
      return [nil, 'HOLD_CACHE_NOT_REGULAR'] unless st.file? && st.size.between?(1, MAX_FILE)
      total += st.size
      return [nil, 'HOLD_CACHE_BUDGET'] if total > MAX_TOTAL
      sources << [expanded, st]
    end
    [sources, 'CATALOG_READY']
  rescue SystemCallError, ArgumentError
    [nil, 'HOLD_CACHE_PATH_OR_ACCESS']
  rescue StandardError
    [nil, 'HOLD_CATALOG_RUNTIME']
  end

  def scratch_folder(parent)
    3.times do
      token = File.binread('/dev/urandom', 8).unpack1('H*')
      folder = File.join(parent, PREFIX + token)
      begin
        Dir.mkdir(folder, 0700)
        return folder
      rescue Errno::EEXIST
        next
      end
    end
    nil
  end

  def clean(folder, parent)
    return false unless folder.is_a?(String) &&
      folder.start_with?(File.expand_path(parent) + '/' + PREFIX) &&
      File.basename(folder).match?(/\Aai_rule_bytecopy_[0-9a-f]{16}\z/) &&
      File.directory?(folder) && !File.symlink?(folder)
    Dir.entries(folder).each do |name|
      next if name == '.' || name == '..'
      return false unless name.match?(/\Acache_\d{4}\z/)
      target = File.join(folder, name)
      return false unless File.file?(target) && !File.symlink?(target)
      File.delete(target)
    end
    Dir.rmdir(folder)
    true
  rescue StandardError
    false
  end

  def copy_and_compare(sources, scratch_parent: '/tmp')
    return ['HOLD_INPUT_LAYOUT', 0, 'NOT_CREATED'] unless sources.is_a?(Array) &&
      sources.size.between?(1, MAX_PROVIDERS)
    folder = nil
    count = 0
    status = 'HOLD_PRIVATE_SCRATCH'
    cleanup = 'NOT_CREATED'
    total = 0
    begin
      folder = scratch_folder(scratch_parent)
      if folder
        cleanup = 'PENDING'
        status = 'BYTE_COPY_VERIFIED'
        sources.each_with_index do |(source, planned), index|
          raise IOError unless File.realpath(source) == source && !File.symlink?(source)
          raise IOError unless same_file?(File.lstat(source), planned)
          dest = File.join(folder, format('cache_%04d', index))
          before = nil
          copied = 0
          flags = File::RDONLY | (File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0)
          File.open(source, flags) do |input|
            before = input.stat
            raise IOError unless before.file? && same_file?(before, planned)
            File.open(dest, File::WRONLY | File::CREAT | File::EXCL, 0600) do |output|
              while (chunk = input.read(CHUNK))
                copied += chunk.bytesize
                total += chunk.bytesize
                raise IOError if copied > MAX_FILE || total > MAX_TOTAL
                output.write(chunk)
              end
            end
            raise IOError unless copied == planned.size
            input.rewind
            File.open(dest, File::RDONLY) do |check|
              while (chunk = input.read(CHUNK))
                raise IOError unless check.read(chunk.bytesize) == chunk
              end
              raise IOError unless check.read(1).nil?
            end
            raise IOError unless same_file?(input.stat, before)
          end
          raise IOError unless same_file?(File.lstat(source), planned)
          count += 1
        end
      end
    rescue StandardError
      status = 'HOLD_CACHE_CHANGED_OR_IO'
    ensure
      if folder
        cleanup = clean(folder, scratch_parent) ? 'YES' : 'FAILED'
        status = 'HOLD_TEMP_CLEANUP' if cleanup == 'FAILED'
      end
    end
    [status, count, cleanup]
  end

  def run
    File.umask(0077)
    puts 'RULE_CACHE_BYTECOPY=START ON_DEVICE_ONLY=YES'
    located = active_config
    unless located
      puts 'BYTECOPY_RESULT=HOLD_CORE_NOT_UNIQUE'
      puts 'PRODUCTION_CONFIG=UNCHANGED PRIVATE_CONFIG_TEST=NOT_RUN AUTO_SWITCH=OFF'
      return
    end
    source, home = located
    raw = File.binread(source, MAX_CONFIG + 1)
    unless raw.bytesize.between?(1, MAX_CONFIG)
      puts 'BYTECOPY_RESULT=HOLD_CONFIG_SIZE'
      return
    end
    config = Psych.safe_load(raw, aliases: false)
    sources, status = catalog(config, home)
    if sources.nil?
      puts "BYTECOPY_RESULT=#{status}"
      puts 'PRODUCTION_CONFIG=UNCHANGED PRIVATE_CONFIG_TEST=NOT_RUN AUTO_SWITCH=OFF'
      return
    end
    result, count, cleanup = copy_and_compare(sources)
    puts "BYTECOPY_RESULT=#{result}"
    puts "CACHE_FILES_VERIFIED=#{count}"
    puts "TEMP_CLEANUP=#{cleanup}"
    puts 'CACHE_SEMANTICS=NOT_VALIDATED GEO_DOWNLOADS=NOT_TESTED'
    puts 'PRODUCTION_CONFIG=UNCHANGED PRIVATE_CONFIG_TEST=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  rescue StandardError
    puts 'BYTECOPY_RESULT=HOLD_READ_ONLY_RUNTIME'
    puts 'PRODUCTION_CONFIG=UNCHANGED PRIVATE_CONFIG_TEST=NOT_RUN AUTO_SWITCH=OFF'
  end
end

AiRuleCacheByteCopyGate.run if __FILE__ == $PROGRAM_NAME
