#!/usr/bin/env ruby
# frozen_string_literal: true
# Controller socket ownership DIAGNOSTIC ONLY. No HTTP, core spawn, or writes.
# Input data never printed. Requires only device-confirmed Psych.
require 'psych'

module AiControllerSocketDiagnostic
  module_function
  CORE_ROOT = '/etc/openclash/core/'
  CONFIG_LIMIT = 20_000_000
  PROC_LINES_LIMIT = 20000
  FD_ENTRIES_LIMIT = 20000

  def flag(args,key)
    idx=args.index(key)
    return args[idx+1] if idx && idx+1<args.size
    args.find { |v| v.start_with?("#{key}=") }&.split('=',2)&.last
  end

  def one_core
    hits=[]
    Dir['/proc/[0-9]*/cmdline'].each do |path|
      begin
        pid=path.split('/')[2]
        next unless File.readlink("/proc/#{pid}/exe").start_with?(CORE_ROOT)
        args=File.binread(path).split("\0")
        next if args.any? { |v| %w[/tmp/openclash-ai- /tmp/openclash-probe- /tmp/oc-ai-].any? {|prefix| v.include?(prefix)} }
        cwd=File.readlink("/proc/#{pid}/cwd")
        home=File.expand_path(flag(args,'-d') || cwd,cwd)
        config=File.expand_path(flag(args,'-f') || 'config.yaml',home)
        next unless File.file?(config) && File.size(config).between?(1,CONFIG_LIMIT)
        hits << [pid,args,config]
      rescue StandardError
        next
      end
    end
    hits.size==1 ? hits.first : nil
  end

  def controller_port(addr)
    m=/\A(?:127\.0\.0\.1|0\.0\.0\.0):([0-9]{1,5})\z/.match(addr.to_s)
    return nil unless m && m[1].to_i.between?(1,65535)
    m[1].to_i
  end

  def bind_class(addr)
    return 'IPV4_LOOPBACK' if addr.to_s.start_with?('127.0.0.1:')
    return 'IPV4_WILDCARD' if addr.to_s.start_with?('0.0.0.0:')
    'OTHER'
  end

  def socket_rows(lines,port,ipv6:false)
    matches=[]
    seen=0
    lines.each do |line|
      seen+=1
      return [nil,'HOLD_PROC_LINES_BUDGET'] if seen>PROC_LINES_LIMIT
      fields=line.split
      next unless fields.size>9 && fields[3]=='0A'
      ip,hex=fields[1].split(':',2)
      next unless hex && hex.to_i(16)==port && fields[9].match?(/\A[0-9]+\z/)
      # IPv6 address is deliberately NEVER decoded or displayed; only AF matters.
      classification = if ipv6
        'IPV6'
      elsif ip.upcase=='0100007F'
        'IPV4_LOOPBACK'
      elsif ip.upcase=='00000000'
        'IPV4_WILDCARD'
      else
        'IPV4_OTHER'
      end
      matches << [classification,fields[9]]
    end
    [matches,'OK']
  end

  def socket_table(pid,port,which)
    path="/proc/#{pid}/net/#{which}"
    File.open(path,'r') do |f|
      header=f.gets
      return [nil,'HOLD_PROC_LAYOUT'] unless header
      socket_rows(f,port,ipv6:(which=='tcp6'))
    end
  rescue StandardError
    [nil,'HOLD_PROC_READ']
  end

  def core_fd_inodes(pid)
    fds=Dir["/proc/#{pid}/fd/*"]
    return [nil,'HOLD_FD_BUDGET'] if fds.length>FD_ENTRIES_LIMIT
    inodes={}
    unreadable=0
    fds.each do |fd|
      begin
        value=File.readlink(fd)
        m=/\Asocket:\[([0-9]+)\]\z/.match(value)
        inodes[m[1]]=true if m
      rescue StandardError
        unreadable+=1
      end
    end
    return [nil,'HOLD_FD_UNREADABLE'] if fds.empty? || unreadable>0
    [inodes,'OK']
  rescue StandardError
    [nil,'HOLD_FD_READ']
  end

  def owner_diagnosis(v4,v6,inodes)
    return nil unless v4.is_a?(Array) && v6.is_a?(Array) && inodes.is_a?(Hash)
    all=v4+v6
    counts={
      'TCP4_PORT_LOOPBACK'=>v4.count{|r|r[0]=='IPV4_LOOPBACK'},
      'TCP4_PORT_WILDCARD'=>v4.count{|r|r[0]=='IPV4_WILDCARD'},
      'TCP4_PORT_OTHER'=>v4.count{|r|r[0]=='IPV4_OTHER'},
      'TCP6_PORT_LISTEN'=>v6.length,
      'CORE_FD_PORT_MATCH'=>all.count{|r|inodes.key?(r[1])}
    }
    owned_v4=v4.any?{|r|inodes.key?(r[1]) && %w[IPV4_LOOPBACK IPV4_WILDCARD].include?(r[0])}
    owned_v6=v6.any?{|r|inodes.key?(r[1])}
    counts['OWNER_EVIDENCE']=if owned_v4
      'IPV4_CORE_SOCKET'
    elsif owned_v6
      'IPV6_CORE_SOCKET_ONLY'
    elsif all.empty?
      'NO_LISTENER_AT_PORT'
    else
      'LISTENER_NOT_MATCHED_TO_CORE_FD'
    end
    counts
  end

  def netns_same(pid)
    a=File.readlink('/proc/self/ns/net')
    b=File.readlink("/proc/#{pid}/ns/net")
    a==b ? 'YES' : 'NO'
  rescue StandardError
    'UNKNOWN'
  end

  def run
    puts 'SOCKET_OWNER_DIAG=START READ_ONLY_NO_HTTP=YES'
    core=one_core
    unless core
      puts 'SOCKET_DIAG_RESULT=HOLD_CORE_NOT_UNIQUE'
      return
    end
    pid,args,conf=core
    raw=File.binread(conf,CONFIG_LIMIT+1)
    unless raw.bytesize.between?(1,CONFIG_LIMIT)
      puts 'SOCKET_DIAG_RESULT=HOLD_CONFIG_SIZE'
      return
    end
    cfg=Psych.safe_load(raw,aliases:false)
    unless cfg.is_a?(Hash) && cfg['rule-providers'].is_a?(Hash) && cfg['rule-providers'].length==20
      puts 'SOCKET_DIAG_RESULT=HOLD_CONFIG_PROVIDER_LAYOUT'
      return
    end
    addr=flag(args,'-ext-ctl') || cfg['external-controller']
    port=controller_port(addr)
    unless port
      puts 'SOCKET_DIAG_RESULT=HOLD_CONTROLLER_BIND_UNSUPPORTED'
      return
    end
    v4,e4=socket_table(pid,port,'tcp')
    v6,e6=socket_table(pid,port,'tcp6')
    fds,ef=core_fd_inodes(pid)
    puts "BIND_CLASS=#{bind_class(addr)}"
    puts "PROC_TCP4_STATUS=#{e4}"
    puts "PROC_TCP6_STATUS=#{e6}"
    puts "CORE_FD_STATUS=#{ef}"
    puts "NETNS_SAME=#{netns_same(pid)}"
    if v4 && v6 && fds
      counts=owner_diagnosis(v4,v6,fds)
      counts.each{|key,value|puts "#{key}=#{value}"}
      puts 'SOCKET_DIAG_RESULT=ANONYMOUS_SOCKET_CLASSIFIED'
    else
      puts 'SOCKET_DIAG_RESULT=HOLD_PROC_EVIDENCE_INCOMPLETE'
    end
    puts 'CONTROLLER_HTTP=NOT_REQUESTED RULE_PROVIDER_CONTENT=NOT_READ'
  rescue StandardError
    puts 'SOCKET_DIAG_RESULT=HOLD_RUNTIME'
  ensure
    puts 'PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  end
end

AiControllerSocketDiagnostic.run if __FILE__==$PROGRAM_NAME
