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

  def core_fd_sockets(pid)
    entries = Dir["/proc/#{pid}/fd/*"]
    return nil if entries.empty? || entries.length > 20_000
    seen = {}
    entries.each do |fd|
      link = File.readlink(fd)
      match = /\Asocket:\[([0-9]+)\]\z/.match(link)
      seen[match[1]] = true if match
    end
    seen
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
    fds = core_fd_sockets(pid)
    owner_class_from_rows(v4, v6, fds)
  rescue StandardError
    nil
  end

  BUILTINS = %w[DIRECT REJECT REJECT-DROP PASS COMPATIBLE GLOBAL].freeze
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
      gnames.uniq == gnames && (names & (gnames + BUILTINS)).empty?
    [{ 'leaves' => names, 'groups' => gnames }, 'SNAPSHOT_READY']
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
    # Unaccounted runtime groups are NOT eligible for AI or treated as leaves.
    unaccounted_groups = all.count { |n, x|
      GROUP_TYPES.include?(x['type']) && !groups.include?(n) && !BUILTINS.include?(n)
    }
    leaves = all.keys.reject { |n|
      groups.include?(n) || BUILTINS.include?(n) ||
        GROUP_TYPES.include?(all[n]['type'])
    }
    present = (leaves & names).length
    missing = names.length - present
    extra = (leaves - names).length
    expected_as_group = names.count { |n|
      all.key?(n) && GROUP_TYPES.include?(all[n]['type'])
    }
    counts = {
      'CONFIG_EMBEDDED_LEAF_COUNT' => names.length,
      'CONFIG_PROXY_PROVIDER_COUNT' => 0,
      'API_EXPECTED_LEAF_PRESENT' => present,
      'API_EXPECTED_LEAF_MISSING' => missing,
      'API_EXTRA_UNTRUSTED_LEAF' => extra,
      'API_UNACCOUNTED_GROUP' => unaccounted_groups,
      'API_EXPECTED_AS_GROUP' => expected_as_group
    }
    result = if missing == 0 && extra == 0 && expected_as_group == 0 &&
        unaccounted_groups == 0
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
    evidence = listener_evidence(pid,port)
    unless evidence
      puts 'LEAF_INVENTORY_RESULT=HOLD_CONTROLLER_OWNER_UNKNOWN'
      return
    end
    response = api_read(secret,port)
    unless evidence == listener_evidence(pid,port)
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
