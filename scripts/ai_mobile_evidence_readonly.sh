umask 077
ruby -rpsych <<'RUBY'
# encoding: UTF-8
# Inline exact fixed-candidate read-only modules. No GitHub download and no local files.
module AiRefreshSchedule
  module_function
  def status(key_values)
    auto = key_values['auto_update'].to_s
    mode = key_values['config_auto_update_mode'].to_s
    out = {
      'auto_update' => auto == '1' ? 'ENABLED' : auto == '0' ? 'DISABLED' : 'UNKNOWN',
      'mode' => 'UNKNOWN',
      'schedule' => 'UNKNOWN'
    }
    return out if out['auto_update'] != 'ENABLED'
    if mode == '0'
      out['mode'] = 'APPOINTMENT'
      week = key_values['config_update_week_time'].to_s
      out['schedule'] = week == '*' ? 'DAILY' : week.match?(/\A[0-6]\z/) ? 'WEEKLY' : 'UNKNOWN'
    elsif mode == '1'
      out['mode'] = 'LOOP'
      raw = key_values['config_update_interval'].to_s
      out['schedule'] = raw.match?(/\A[1-9]\d*\z/) && raw.to_i.between?(1, 10_080) ? 'PERIODIC' : 'UNKNOWN'
    end
    out
  end
  def age_bucket(mtime, now = Time.now)
    diff = now - mtime
    diff < 0 ? 'FUTURE' : diff < 86_400 ? 'LT24H' : diff < 604_800 ? 'LT7D' : 'OLDER'
  end
  def safe_source_file(selected)
    return nil unless selected.is_a?(String) && !selected.empty?
    root = '/etc/openclash/config/'
    path = File.expand_path(selected.start_with?('/') ? selected : File.join(root, selected))
    return nil unless path.start_with?(root) && File.file?(path) && File.size(path).between?(1, 20_000_000)
    return nil unless File.realpath(path).start_with?(root)
    path
  rescue StandardError
    nil
  end
  def live_core_config
    Dir['/proc/[0-9]*/cmdline'].each do |f|
      begin
        pid = f.split('/')[2]
        exe = File.readlink("/proc/#{pid}/exe")
        next unless exe.start_with?('/etc/openclash/core/')
        argv = File.binread(f).split("\0")
        next if argv.any? { |x| x.include?('/tmp/openclash-ai-') || x.include?('/tmp/openclash-probe-') }
        cwd = File.readlink("/proc/#{pid}/cwd")
        pos = argv.index('-d')
        dir = File.expand_path(pos ? argv[pos + 1] : cwd, cwd)
        pos = argv.index('-f')
        path = File.expand_path(pos ? argv[pos + 1] : 'config.yaml', dir)
        return path if File.file?(path) && File.size(path).between?(1, 20_000_000)
      rescue StandardError
        next
      end
    end
    nil
  end
  def disk_definitions_match?(left, right)
    a = Psych.safe_load(File.binread(left), aliases: false)
    b = Psych.safe_load(File.binread(right), aliases: false)
    raise 'no embedded proxies' unless a.is_a?(Hash) && b.is_a?(Hash) && a['proxies'].is_a?(Array) && b['proxies'].is_a?(Array)
    a['proxies'] == b['proxies']
  end
  def uci_read(key)
    IO.popen(['uci', '-q', 'get', "openclash.config.#{key}"], err: File::NULL) { |io| io.read.to_s.strip }
  rescue StandardError
    ''
  end
  def run
    keys = %w[auto_update config_auto_update_mode config_update_week_time auto_update_time config_update_interval]
    values = keys.to_h { |k| [k, uci_read(k)] }
    sched = status(values)
    puts "SCHEDULE_AUTO_UPDATE=#{sched['auto_update']} MODE=#{sched['mode']} CADENCE=#{sched['schedule']}"
    puts 'SCHEDULE_SETTINGS=READ_ONLY'
    source = safe_source_file(uci_read('config_path'))
    live = live_core_config
    puts "SOURCE_DISK=#{source ? 'READABLE' : 'UNAVAILABLE'} RUNTIME_CONFIG_DISK=#{live ? 'READABLE' : 'UNAVAILABLE'}"
    puts "SOURCE_FILE_AGE=#{source ? age_bucket(File.mtime(source)) : 'UNAVAILABLE'}"
    matched = if source && live
      begin
        disk_definitions_match?(source, live) ? 'MATCH' : 'DIFFER'
      rescue StandardError
        'UNAVAILABLE'
      end
    else
      'UNAVAILABLE'
    end
    puts "SOURCE_RUNTIME_DISK_DEFINITIONS=#{matched}"
    puts 'REMOTE_UPDATE_SUCCESS=UNVERIFIED'
    puts 'Mihomo_RELOAD_CONFIRMED=NO'
    puts 'AI_MONITOR_INSTALLED=NO'
    # No candidate is activated by this tool. Never read logs with raw URLs.
    0
  rescue StandardError
    puts 'READONLY_SCHEDULE=UNAVAILABLE_NO_PRIVATE_OUTPUT'
    2
  end
end

module AiRefreshActivationGate
  module_function
  MAX_AGE = 2 * 86_400
  # Parse local OpenClash log timestamps using Ruby core only (OpenWrt ruby-core
  # may not ship the optional 'time' stdlib). Reject invalid/normalized dates.
  def parse_log_timestamp(raw)
    parts = raw.split(/[- :]/).map { |v| Integer(v, 10) }
    return nil unless parts.length == 6
    year, month, day, hour, minute, second = parts
    return nil unless year.between?(2000, 9999) && month.between?(1, 12) &&
                      day.between?(1, 31) && hour.between?(0, 23) &&
                      minute.between?(0, 59) && second.between?(0, 59)
    value = Time.local(year, month, day, hour, minute, second)
    return nil unless [value.year, value.month, value.day, value.hour, value.min, value.sec] == parts
    value
  rescue ArgumentError, RangeError
    nil
  end
  def events(log, alias_name)
    return [] unless log.is_a?(String) && alias_name.is_a?(String) && alias_name.bytesize.between?(1, 256)
    escaped = Regexp.escape(alias_name)
    pattern = /\A(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) \[(?:Info|Error|Tip|Warning)\] (.*?)\z/
    log.lines.filter_map do |line|
      match = pattern.match(line.chomp)
      next unless match
      message = match[2]
      kind = case message
             when /\AConfig File(?:【#{escaped}】|〖#{escaped}〗)Update Successful!\z/
               'UPDATED'
             when /\AConfig File(?:【#{escaped}】|〖#{escaped}〗)No Change, Do Nothing!\z/
               'NO_CHANGE'
             when /\A(?:Config File(?:【#{escaped}】|〖#{escaped}〗)Subscribed Failed.*|(?:【#{escaped}】|〖#{escaped}〗)Update Error.*)\z/
               'FAILED'
             end
      next unless kind
      parsed_time = parse_log_timestamp(match[1])
      parsed_time && [parsed_time, kind]
    end
  end
  def decision(log:, alias_name:, now:, source_mtime:, core_start_time:,
               source_disk_matches_runtime:, single_source:, runtime_core_count:)
    entries = events(log, alias_name)
    entry = entries.last
    return 'NO_LOG_EVENT' unless entry
    time, status = entry
    return 'LOG_STALE_OR_FUTURE' unless (now - time).between?(0, MAX_AGE)
    return 'LATEST_UPDATE_FAILED' if status == 'FAILED'
    return 'NO_CONTENT_CHANGE' if status == 'NO_CHANGE'
    return 'SOURCE_NOT_UNIQUE' unless single_source
    return 'RUNTIME_AMBIGUOUS' unless runtime_core_count == 1
    return 'DISK_DEFINITIONS_DIFFER' unless source_disk_matches_runtime == true
    return 'UNKNOWN_FILE_TIME' unless source_mtime.is_a?(Time)
    return 'SOURCE_CHANGED_AFTER_LOG' if source_mtime > time + 3
    return 'SOURCE_MTIME_TOO_OLD' if source_mtime < time - 180
    return 'CORE_START_UNVERIFIED' unless core_start_time.is_a?(Time)
    return 'CORE_PREDATES_UPDATE' if core_start_time < time - 3 || core_start_time < source_mtime - 3
    return 'CLOCK_INCONSISTENT' if core_start_time > now + 3
    'COLD_START_AFTER_UPDATE_CANDIDATE'
  rescue StandardError
    'EVIDENCE_UNAVAILABLE'
  end
  def selected_source
    selected = IO.popen(['uci','-q','get','openclash.config.config_path'], err: File::NULL) { |io| io.read.to_s.strip }
    return nil unless selected.is_a?(String) && !selected.empty?
    root = '/etc/openclash/config/'
    path = File.expand_path(selected.start_with?('/') ? selected : File.join(root,selected))
    return nil unless path.start_with?(root) && File.file?(path) && File.size(path).between?(1,20_000_000)
    return nil unless File.realpath(path).start_with?(root)
    path
  rescue StandardError
    nil
  end
  def one_source_alias(selected)
    uci = IO.popen(['uci','-q','show','openclash'], err: File::NULL) { |io| io.read.to_s }
    ids = uci.scan(/^openclash\.([^.=]+)=config_subscribe\s*$/).flatten.uniq
    return nil unless ids.length == 1
    key = "openclash.#{ids.first}"
    enabled = IO.popen(['uci','-q','get',"#{key}.enabled"], err: File::NULL) { |io| io.read.to_s.strip }
    name = IO.popen(['uci','-q','get',"#{key}.name"], err: File::NULL) { |io| io.read.to_s.strip }
    name = 'config' if name.empty?
    return nil unless enabled == '1' && name.match?(/\A[^\/\x00-\x1f]{1,128}\z/)
    expected = File.expand_path("/etc/openclash/config/#{name}.yaml")
    selected == expected ? name : nil
  rescue StandardError
    nil
  end
  def core_records
    records = []
    Dir['/proc/[0-9]*/cmdline'].each do |cp|
      begin
        pid = cp.split('/')[2].to_i
        exe = File.readlink("/proc/#{pid}/exe")
        next unless exe.start_with?('/etc/openclash/core/')
        argv = File.binread(cp).split("\0")
        next if argv.any? { |x| x.include?('/tmp/openclash-ai-') || x.include?('/tmp/openclash-probe-') || x.include?('/tmp/oc-ai-') }
        cwd = File.readlink("/proc/#{pid}/cwd")
        opts = ->(key) { idx = argv.index(key); idx ? argv[idx + 1] : argv.find { |v| v.start_with?("#{key}=") }&.split('=',2)&.last }
        dir = File.expand_path(opts.call('-d') || cwd, cwd)
        path = File.expand_path(opts.call('-f') || 'config.yaml', dir)
        next unless File.file?(path) && File.size(path).between?(1,20_000_000)
        records << [pid, path]
      rescue StandardError
        next
      end
    end
    records
  end
  def process_start(pid)
    stat = File.read("/proc/#{pid}/stat")
    tail = stat.split(') ', 2).fetch(1).split
    ticks = Integer(tail.fetch(19)) # proc stat field 22, tail index 19 after fields 1,2
    hz = Integer(IO.popen(['getconf','CLK_TCK'], err: File::NULL) { |io| io.read.to_s.strip })
    uptime = Float(File.read('/proc/uptime').split.first)
    raise 'invalid_clock' unless hz.positive? && uptime.positive? && ticks >= 0
    Time.at(Time.now.to_f - uptime + ticks.to_f / hz)
  end
  def definitions_match?(source, runtime)
    a=Psych.safe_load(File.binread(source), aliases:false)
    b=Psych.safe_load(File.binread(runtime), aliases:false)
    a.is_a?(Hash) && b.is_a?(Hash) &&
      a['proxies'].is_a?(Array) && b['proxies'].is_a?(Array) &&
      a['proxies'] == b['proxies']
  end
  def run
    source = selected_source
    alias_name = source && one_source_alias(source)
    puts "SOURCE_ALIAS_LINK=#{alias_name ? 'MATCH' : 'UNVERIFIED'}"
    cores = core_records
    puts "RUNTIME_CORES=#{cores.length == 1 ? 'ONE' : 'NOT_EXACTLY_ONE'}"
    core_start = cores.length == 1 ? process_start(cores.first[0]) : nil
    disk_match = !!(source && cores.length == 1 && definitions_match?(source,cores.first[1]))
    puts "SOURCE_RUNTIME_DISK_DEFINITIONS=#{disk_match ? 'MATCH' : 'UNVERIFIED_OR_DIFFER'}"
    logfile = '/tmp/openclash.log'
    log = File.file?(logfile) && File.size(logfile).between?(1,1_000_000) ?
       File.binread(logfile).force_encoding('UTF-8').scrub : ''
    proof = decision(log:log, alias_name:alias_name, now:Time.now,
                     source_mtime:source && File.mtime(source),
                     core_start_time:core_start, source_disk_matches_runtime:disk_match,
                     single_source:!!alias_name, runtime_core_count:cores.length)
    puts "POST_UPDATE_ACTIVATION_EVIDENCE=#{proof}"
    puts 'MIHOMO_RUNTIME_API_CONTENT=NOT_QUERIED'
    puts 'REMOTE_DOWNLOAD_EXIT_STATUS=NOT_CAPTURED'
    puts 'FULL_AI_POOL_UPDATE_GATE=BLOCKED_PENDING_RUNTIME_API_AND_SUCCESS_RECEIPT'
    puts 'READ_ONLY=YES PRODUCTION_WRITES=NONE'
    0
  rescue StandardError
    puts 'ACTIVATION_PROBE=UNAVAILABLE_NO_PRIVATE_OUTPUT'
    2
  end
end

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

module AiRefreshLiveEvidenceBundle
  module_function
  def run
    puts 'EVIDENCE_BUNDLE=START READ_ONLY=YES'
    a = AiRefreshActivationGate.run
    b = AiLiveMembership.run
    puts "EVIDENCE_BUNDLE=COMPLETE ACTIVATION_PROBE=#{a.zero? ? 'OBSERVED' : 'UNAVAILABLE'} LIVE_API_PROBE=#{b.zero? ? 'OBSERVED_OR_SAFE_HOLD' : 'UNAVAILABLE'}"
    puts 'AI_CATALOG_RECONCILE=NOT_AUTHORIZED'
    puts 'AI_NODE_SWITCH=NOT_AUTHORIZED'
    0
  rescue StandardError
    puts 'EVIDENCE_BUNDLE=SAFE_STOP_NO_PRIVATE_OUTPUT'
    2
  end
end

exit AiRefreshLiveEvidenceBundle.run
RUBY
