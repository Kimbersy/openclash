#!/usr/bin/env ruby
# frozen_string_literal: true
# Read-only anonymous registration/count census of rule providers from the
# already-running Mihomo local controller. No PUT, provider refresh or core spawn.
# Runtime: Ruby core + device-confirmed Psych, plus existing curl CLI.
require 'psych'

module AiLiveRuleProviderReadOnly
  module_function
  CORE_ROOT = '/etc/openclash/core/'
  MAX_CONFIG_BYTES = 20_000_000
  MAX_RESPONSE_BYTES = 1_500_000
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

  def expected_providers(cfg)
    return nil unless cfg.is_a?(Hash)
    providers = cfg['rule-providers']
    return nil unless providers.is_a?(Hash) && providers.length == 20
    return nil unless providers.all? { |k,v|
      k.is_a?(String) && !k.empty? && k.bytesize <= 256 &&
        v.is_a?(Hash) && v['type'] == 'http' && GROUP_KNOWN.include?(v.fetch('format', 'yaml'))
    }
    providers
  end

  def count_kind(data)
    return 'ABSENT' unless data
    return 'UNKNOWN' unless data.is_a?(Hash)
    n = data['ruleCount']
    return 'UNKNOWN' unless n.is_a?(Integer) && n >= 0
    n == 0 ? 'ZERO' : 'POSITIVE'
  end

  def classify(expected, api)
    return ['HOLD_EXPECTED_PROVIDERS', nil] unless expected.is_a?(Hash) && expected.length == 20
    return ['HOLD_API_LAYOUT', nil] unless api.is_a?(Hash) && api['providers'].is_a?(Hash)
    providers = api['providers']
    return ['HOLD_API_LAYOUT', nil] unless providers.size <= MAX_RULE_PROVIDERS &&
      providers.all? { |k,v| k.is_a?(String) && v.is_a?(Hash) }
    names = expected.keys
    present = names.count { |n| providers.key?(n) }
    missing = names.size - present
    extra = (providers.keys - names).size
    positive = zero = unknown = 0
    names.each do |n|
      next unless providers.key?(n)
      case count_kind(providers[n])
      when 'POSITIVE' then positive += 1
      when 'ZERO' then zero += 1
      else unknown += 1
      end
    end
    mrs = names.select { |n| expected[n].fetch('format','yaml') == 'mrs' }
    return ['HOLD_EXPECTED_MRS_COUNT', nil] unless mrs.size == 1
    status = missing == 0 ? 'API_RULE_PROVIDER_CATALOG_READ' : 'HOLD_RUNTIME_PROVIDER_MISSING'
    [status, {
      'CONFIG_PROVIDER_COUNT' => names.size,
      'API_PROVIDER_COUNT' => providers.size,
      'API_EXPECTED_PRESENT' => present,
      'API_EXPECTED_MISSING' => missing,
      'API_EXTRA_UNTRUSTED' => extra,
      'API_RULECOUNT_POSITIVE' => positive,
      'API_RULECOUNT_ZERO' => zero,
      'API_RULECOUNT_UNKNOWN' => unknown,
      'MRS_RUNTIME_RULECOUNT' => count_kind(providers[mrs.first])
    }]
  end

  def api_read(secret, port)
    return nil unless secret.is_a?(String) && secret.bytesize <= 512 &&
      !secret.match?(/[\x00-\x1f\x7f]/)
    args = ['curl','-q','--ipv4','--noproxy','*','--silent','--fail',
            '--connect-timeout','2','--max-time','7',
            '--max-filesize',MAX_RESPONSE_BYTES.to_s,
            '--proto','=http','--max-redirs','0',
            '--request','GET','--config','-',
            "http://127.0.0.1:#{port}/providers/rules"]
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
    puts 'RULE_PROVIDER_LIVE=START GET_ONLY=YES'
    core = candidate_core
    unless core
      puts 'LIVE_RULE_RESULT=HOLD_CORE_NOT_UNIQUE'
      return
    end
    pid, argv, file = core
    cfg = Psych.safe_load(File.binread(file,MAX_CONFIG_BYTES+1),aliases:false)
    expected = expected_providers(cfg)
    unless expected
      puts 'LIVE_RULE_RESULT=HOLD_CONFIG_PROVIDER_LAYOUT'
      return
    end
    addr = flag(argv,'-ext-ctl') || cfg['external-controller']
    secret = flag(argv,'-secret') || cfg['secret'] || ''
    port = controller_port(addr)
    unless port
      puts 'LIVE_RULE_RESULT=HOLD_CONTROLLER_NON_LOOPBACK'
      return
    end
    evidence = listener_evidence(pid,port)
    unless evidence
      puts 'LIVE_RULE_RESULT=HOLD_CONTROLLER_OWNER_UNKNOWN'
      return
    end
    response = api_read(secret,port)
    unless evidence == listener_evidence(pid,port)
      puts 'LIVE_RULE_RESULT=HOLD_CONTROLLER_OWNER_CHANGED'
      return
    end
    unless response
      puts 'LIVE_RULE_RESULT=HOLD_IPV4_LOCAL_API_UNAVAILABLE'
      return
    end
    puts "CONTROLLER_TRANSPORT=IPV4_LOOPBACK"
    puts "SOCKET_OWNER_CLASS=#{evidence[0]}"
    status, counters = classify(expected,response)
    puts "LIVE_RULE_RESULT=#{status}"
    counters&.each { |key,val| puts "#{key}=#{val}" }
    puts 'API_NAMES_AND_CREDENTIALS=NOT_EMITTED'
    puts 'PROVIDER_REGISTRATION_ONLY=YES DISK_MATCH=NOT_PROVEN REMOTE_UPDATE=NOT_PROVEN'
    puts 'MRS_BINARY_FORMAT=UNVERIFIED AI_BUSINESS=UNKNOWN'
  rescue StandardError
    puts 'LIVE_RULE_RESULT=HOLD_RUNTIME_OR_JSON'
  ensure
    puts 'PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  end
end

AiLiveRuleProviderReadOnly.run if __FILE__ == $PROGRAM_NAME
