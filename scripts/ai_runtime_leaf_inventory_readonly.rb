#!/usr/bin/env ruby
# frozen_string_literal: true
# Current embedded-leaf name coverage vs the already-running Mihomo local API.
# No PUT, proxy switch, provider refresh, core spawn or private name output.
# Runtime: Ruby core + device-confirmed Psych, plus existing curl CLI.
require 'psych'

module AiRuntimeLeafNamesReadOnly
  module_function
  CORE_ROOT = '/etc/openclash/core/'
  MAX_CONFIG_BYTES = 20_000_000
  MAX_RESPONSE_BYTES = 3_000_000
  MAX_RULE_PROVIDERS = 2000
  GROUP_KNOWN = %w[yaml text mrs].freeze

  def flag(args, key)
    idx = args.index(key)
    return args[idx + 1] if idx && idx + 1 < args.length
    args.find { |s| s.start_with?(key + '=') }&.split('=', 2)&.last
  end

  def candidate_core
    hits = []
    Dir['/proc/[0-9]*/cmdline'].each do |p|
      begin
        pid = p.split('/')[2]
        next unless File.readlink("/proc/#{pid}/exe").start_with?(CORE_ROOT)
        argv = File.binread(p).split("\0")
        next if argv.any? { |a| %w[/tmp/openclash-ai- /tmp/openclash-probe- /tmp/oc-ai-].any? { |x| a.include?(x) } }
        cwd = File.readlink("/proc/#{pid}/cwd")
        home = File.expand_path(flag(argv, '-d') || cwd, cwd)
        config = File.expand_path(flag(argv, '-f') || 'config.yaml', home)
        next unless File.file?(config) && File.size(config).between?(1, MAX_CONFIG_BYTES)
        hits << [pid, argv, config]
      rescue StandardError
        next
      end
    end
    hits.size == 1 ? hits.first : nil
  end

  def controller_port(address)
    # Even if the controller listens on all IPs, the probe only connects to 127.0.0.1.
    m = /\A(?:127\.0\.0\.1|0\.0\.0\.0):([0-9]{1,5})\z/.match(address.to_s)
    return nil unless m && m[1].to_i.between?(1, 65_535)
    m[1].to_i
  end

  # "IPv6 socket" is a listener implementation detail, NOT the egress
  # protocol. We only contact 127.0.0.1 with curl --ipv4; NEVER use ::1.
  def socket_rows(file, port, v6: false)
    rows = []
    limit = 0
    File.open(file, 'r') do |io|
      return nil unless io.gets
      io.each_line do |line|
        limit += 1
        return nil if limit > 20_000
        fields = line.split
        next unless fields.length > 9 && fields[3] == '0A'
        address, hex = fields[1].split(':', 2)
        next unless hex && hex.match?(/\A[0-9A-Fa-f]{4}\z/) &&
          hex.to_i(16) == port && fields[9].match?(/\A[0-9]+\z/)
        klass = if v6
          address.match?(/\A0{32}\z/) ? 'IPV6_WILDCARD' : 'IPV6_OTHER'
        elsif address.upcase == '0100007F'
          'IPV4_LOOPBACK'
        elsif address.upcase == '00000000'
          'IPV4_WILDCARD'
        else
          'IPV4_OTHER'
        end
        rows << [klass, fields[9]]
      end
    end
    rows
  rescue StandardError
    nil
  end

  # Enumerating /proc/PID/fd is racy: temporary connection FDs can disappear
  # between readdir and readlink. Only the actual target LISTEN inode proves
  # ownership. Ignore ENOENT/EBADF on unrelated vanished FDs, NEVER infer
  # ownership from an unreadable listener or a different socket.
  def match_listener_fds(entries, target_inodes, reader = nil)
    return nil unless entries.is_a?(Array) && !entries.empty? &&
      entries.size <= 20_000 && target_inodes.is_a?(Array) &&
      target_inodes.length.between?(1, 1000) &&
      target_inodes.all? { |n| n.is_a?(String) && n.match?(/\A[0-9]+\z/) }
    want = {}
    target_inodes.each { |n| want[n] = true }
    got = {}
    reader ||= ->(fd) { File.readlink(fd) }
    entries.each do |fd|
      begin
        value = reader.call(fd)
      rescue Errno::ENOENT, Errno::EBADF
        # A closed non-listener FD is common during API activity. If the
        # listener FD vanished, no matching inode will be found -> HOLD.
        next
      end
      m = /\Asocket:\[([0-9]+)\]\z/.match(value)
      got[m[1]] = true if m && want[m[1]]
    end
    got
  rescue StandardError
    nil
  end

  def core_fd_sockets(pid, target_inodes)
    entries = Dir["/proc/#{pid}/fd/*"]
    match_listener_fds(entries, target_inodes)
  rescue StandardError
    nil
  end

  def proc_starttime(stat)
    return nil unless stat.is_a?(String)
    close = stat.rindex(')')
    return nil unless close
    # Linux /proc/PID/stat fields 3 onward begin after closing "(comm)".
    # starttime is field 22, which is the 20th field of this suffix.
    value = stat[(close + 1)..-1].split[19]
    value if value && value.match?(/\A[0-9]+\z/)
  end

  def core_process_identity(pid)
    exe = File.readlink("/proc/#{pid}/exe")
    return nil unless exe.start_with?(CORE_ROOT)
    ns = File.readlink("/proc/#{pid}/ns/net")
    raw = File.binread("/proc/#{pid}/stat", 8192)
    starttime = proc_starttime(raw)
    return nil unless starttime
    [exe, ns, starttime]
  rescue StandardError
    nil
  end

  def owner_class_from_rows(v4, v6, owned)
    return nil unless v4.is_a?(Array) && v6.is_a?(Array) && owned.is_a?(Hash)
    return nil unless (v4 + v6).all? { |r| r.is_a?(Array) && r.length == 2 }
    # Any IPv4 listener not owned by the unique core could receive a loopback
    # Bearer request. Do not send an HTTP request in that case.
    return nil if v4.any? { |klass, ino|
      !owned[ino] || !%w[IPV4_LOOPBACK IPV4_WILDCARD].include?(klass)
    }
    return ['IPV4_CORE_SOCKET', (v4 + v6).map(&:last).sort] unless v4.empty?
    # Actual 20:54 iStoreOS: config 0.0.0.0, TCP4=0, one TCP6 core
    # socket. Only :: wildcard can potentially accept IPv4-mapped clients.
    # ::1 and other remote IPv6 binds are NEVER used as fallback.
    return nil unless v6.length == 1 && v6[0][0] == 'IPV6_WILDCARD' &&
      owned[v6[0][1]]
    ['IPV6_WILDCARD_IPV4_CANDIDATE', v6.map(&:last)]
  end

  def listener_evidence(pid, port)
    return nil unless File.readlink('/proc/self/ns/net') ==
      File.readlink("/proc/#{pid}/ns/net")
    v4 = socket_rows("/proc/#{pid}/net/tcp", port)
    v6 = socket_rows("/proc/#{pid}/net/tcp6", port, v6: true)
    return nil unless v4 && v6
    listen_inodes = (v4 + v6).map(&:last)
    return nil if listen_inodes.empty?
    fds = core_fd_sockets(pid, listen_inodes)
    owner_class_from_rows(v4, v6, fds)
  rescue StandardError
    nil
  end

  # Official Mihomo preset names: ignore ONLY when API type also matches.
  # PASS-RULE was absent in the earlier list and may account for one extra.
  # Unknown entries must never silently become trusted AI leaf nodes.
  BUILTIN_NAME_TYPE = {
    'DIRECT' => 'Direct', 'REJECT' => 'Reject',
    'REJECT-DROP' => 'RejectDrop', 'PASS' => 'Pass',
    'PASS-RULE' => 'PassRule', 'COMPATIBLE' => 'Compatible',
    'GLOBAL' => 'Selector'
  }.freeze
  BUILTINS = BUILTIN_NAME_TYPE.keys.freeze
  GROUP_TYPES = %w[Selector URLTest Fallback LoadBalance Relay Compatible].freeze

  def expected_leaf_snapshot(cfg)
    return [nil, 'HOLD_CONFIG_LAYOUT'] unless cfg.is_a?(Hash)
    embedded = cfg['proxies']
    return [nil, 'HOLD_EMBEDDED_LAYOUT'] unless embedded.is_a?(Array) &&
      embedded.length.between?(1, 5000) &&
      embedded.all? { |x| x.is_a?(Hash) && x['name'].is_a?(String) &&
        !x['name'].empty? && x['name'].bytesize <= 256 &&
        x['type'].is_a?(String) }
    return [nil, 'HOLD_PROXY_PROVIDER_MODE'] unless
      cfg['proxy-providers'].nil? || cfg['proxy-providers'] == {}
    groups = cfg['proxy-groups']
    return [nil, 'HOLD_GROUP_LAYOUT'] unless groups.is_a?(Array) &&
      groups.all? { |x| x.is_a?(Hash) && x['name'].is_a?(String) }
    names = embedded.map { |x| x['name'] }
    gnames = groups.map { |x| x['name'] }
    return [nil, 'HOLD_NAME_COLLISION'] unless names.uniq == names &&
      gnames.uniq == gnames && (names & (gnames + BUILTINS)).empty? &&
      (gnames & BUILTINS).empty?
    [{ 'leaves' => names, 'groups' => gnames }, 'SNAPSHOT_READY']
  end

  def extra_classification(snapshot, api)
    return nil unless snapshot.is_a?(Hash) && api.is_a?(Hash) &&
      api['proxies'].is_a?(Hash)
    expected = snapshot['leaves'] + snapshot['groups']
    counts = {'API_EXTRA_PRESET_MATCHED' => 0,
              'API_PASS_RULE_PRESET' => 0,
              'API_EXTRA_PRESET_TYPE_MISMATCH' => 0,
              'API_EXTRA_SPECIAL_TYPE_UNCLASSIFIED' => 0,
              'API_EXTRA_OTHER_UNCLASSIFIED' => 0}
    api['proxies'].each do |n, value|
      next if expected.include?(n)
      type = value['type']
      if BUILTIN_NAME_TYPE.key?(n)
        if type == BUILTIN_NAME_TYPE[n]
          counts['API_EXTRA_PRESET_MATCHED'] += 1
          counts['API_PASS_RULE_PRESET'] += 1 if n == 'PASS-RULE'
        else
          counts['API_EXTRA_PRESET_TYPE_MISMATCH'] += 1
        end
      elsif %w[PassRule Pass Rematch Dns RejectDrop].include?(type)
        counts['API_EXTRA_SPECIAL_TYPE_UNCLASSIFIED'] += 1
      else
        counts['API_EXTRA_OTHER_UNCLASSIFIED'] += 1
      end
    end
    counts
  end

  def compare_snapshot(snapshot, api)
    return [nil, 'HOLD_EXPECTED_LAYOUT'] unless snapshot.is_a?(Hash) &&
      snapshot['leaves'].is_a?(Array) && snapshot['groups'].is_a?(Array)
    return [nil, 'HOLD_API_LAYOUT'] unless api.is_a?(Hash) &&
      api['proxies'].is_a?(Hash) && api['proxies'].size <= 6000 &&
      api['proxies'].all? { |n, x| n.is_a?(String) && x.is_a?(Hash) &&
        x['type'].is_a?(String) }
    names = snapshot['leaves']
    groups = snapshot['groups']
    all = api['proxies']
    extra = extra_classification(snapshot, api)
    # No name-based exclusion without checking official preset API type.
    # A newly named "PASS-RULE" of type "Trojan" is NOT a preset.
    unaccounted_groups = all.count { |n, x|
      GROUP_TYPES.include?(x['type']) && !groups.include?(n) &&
        BUILTIN_NAME_TYPE[n] != x['type']
    }
    leaves = all.keys.reject { |n|
      groups.include?(n) || BUILTIN_NAME_TYPE[n] == all[n]['type'] ||
        GROUP_TYPES.include?(all[n]['type'])
    }
    present = (leaves & names).length
    missing = names.length - present
    # Include both unknown leaf candidates and reserved-name/type mismatches.
    unknown_extra = extra['API_EXTRA_PRESET_TYPE_MISMATCH'] +
      extra['API_EXTRA_SPECIAL_TYPE_UNCLASSIFIED'] +
      extra['API_EXTRA_OTHER_UNCLASSIFIED']
    expected_as_group = names.count { |n|
      all.key?(n) && GROUP_TYPES.include?(all[n]['type'])
    }
    counts = {
      'CONFIG_EMBEDDED_LEAF_COUNT' => names.length,
      'CONFIG_PROXY_PROVIDER_COUNT' => 0,
      'API_EXPECTED_LEAF_PRESENT' => present,
      'API_EXPECTED_LEAF_MISSING' => missing,
      'API_EXTRA_UNTRUSTED_LEAF' => unknown_extra,
      'API_UNACCOUNTED_GROUP' => unaccounted_groups,
      'API_EXPECTED_AS_GROUP' => expected_as_group
    }.merge(extra)
    result = if missing == 0 && unknown_extra == 0 &&
        expected_as_group == 0 && unaccounted_groups == 0
      'LIVE_LEAF_NAME_COVERAGE_PASS'
    else
      'HOLD_RUNTIME_LEAF_MISMATCH'
    end
    [counts,result]
  end

  def api_read(secret, port)
    return nil unless secret.is_a?(String) && secret.bytesize <= 512 &&
      !secret.match?(/[\x00-\x1f\x7f]/)
    args = ['curl','-q','--ipv4','--noproxy','*','--silent','--fail',
            '--connect-timeout','2','--max-time','7',
            '--max-filesize',MAX_RESPONSE_BYTES.to_s,
            '--proto','=http','--max-redirs','0',
            '--request','GET','--config','-',
            "http://127.0.0.1:#{port}/proxies"]
    body = ''
    IO.popen(args, 'r+', err: File::NULL) do |io|
      unless secret.empty?
        escaped = secret.gsub(/[\\"]/) { |c| '\\' + c }
        io.write("header = \"Authorization: Bearer #{escaped}\"\n")
      end
      io.close_write
      body = io.read(MAX_RESPONSE_BYTES + 1)
    end
    return nil unless $?.success? && body.bytesize.between?(2,MAX_RESPONSE_BYTES)
    parsed = Psych.safe_load(body, aliases:false)
    parsed.is_a?(Hash) ? parsed : nil
  rescue StandardError
    nil
  end

  def run
    puts 'RUNTIME_LEAF_INVENTORY=START GET_ONLY_IPV4=YES'
    core = candidate_core
    unless core
      puts 'LEAF_INVENTORY_RESULT=HOLD_CORE_NOT_UNIQUE'
      return
    end
    pid, argv, file = core
    raw = File.binread(file,MAX_CONFIG_BYTES+1)
    unless raw.bytesize.between?(1,MAX_CONFIG_BYTES)
      puts 'LEAF_INVENTORY_RESULT=HOLD_CONFIG_SIZE'
      return
    end
    cfg = Psych.safe_load(raw,aliases:false)
    snapshot, gate = expected_leaf_snapshot(cfg)
    unless snapshot
      puts "LEAF_INVENTORY_RESULT=#{gate}"
      return
    end
    addr = flag(argv,'-ext-ctl') || cfg['external-controller']
    secret = flag(argv,'-secret') || cfg['secret'] || ''
    port = controller_port(addr)
    unless port
      puts 'LEAF_INVENTORY_RESULT=HOLD_CONTROLLER_NON_LOOPBACK'
      return
    end
    identity_before = core_process_identity(pid)
    unless identity_before
      puts 'LEAF_INVENTORY_RESULT=HOLD_CORE_IDENTITY_UNKNOWN'
      return
    end
    evidence = listener_evidence(pid,port)
    unless evidence
      puts 'LEAF_INVENTORY_RESULT=HOLD_CONTROLLER_OWNER_UNKNOWN'
      return
    end
    response = api_read(secret,port)
    unless identity_before == core_process_identity(pid)
      puts 'LEAF_INVENTORY_RESULT=HOLD_CORE_PROCESS_CHANGED'
      return
    end
    evidence_after = listener_evidence(pid,port)
    unless evidence_after
      puts 'LEAF_INVENTORY_RESULT=HOLD_CONTROLLER_OWNER_RECHECK_UNAVAILABLE'
      return
    end
    unless evidence == evidence_after
      puts 'LEAF_INVENTORY_RESULT=HOLD_CONTROLLER_OWNER_CHANGED'
      return
    end
    unless response
      puts 'LEAF_INVENTORY_RESULT=HOLD_IPV4_API_UNAVAILABLE'
      return
    end
    counters, status = compare_snapshot(snapshot,response)
    puts "LEAF_INVENTORY_RESULT=#{status}"
    counters&.each { |key,val| puts "#{key}=#{val}" }
    puts 'API_TRANSPORT=IPV4_LOOPBACK'
    puts 'LEAF_NAMES_EMITTED=NO PROXY_DETAILS_EMITTED=NO'
    puts 'LIVE_FULL_CONNECTION_FINGERPRINTS=NOT_VERIFIED'
    puts 'ENABLED_SUBSCRIPTION_SOURCE_COVERAGE=NOT_VERIFIED'
    puts 'AI_BUSINESS=UNKNOWN NODE_SWITCH=NOT_RUN'
  rescue StandardError
    puts 'LEAF_INVENTORY_RESULT=HOLD_RUNTIME'
  ensure
    puts 'PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  end

end

AiRuntimeLeafNamesReadOnly.run if __FILE__ == $PROGRAM_NAME
