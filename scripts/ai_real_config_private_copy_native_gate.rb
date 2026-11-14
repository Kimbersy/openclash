#!/usr/bin/env ruby
# frozen_string_literal: true
# PRIVATE, FAIL-CLOSED OpenClash source-config overlay candidate. No install.
# Only psych is required (confirmed on iStoreOS in 15:02 receipt).
# No source YAML/password/node/server/request/diagnostic text leaves router.
# This script may temporarily write a private copy and run an isolated -t.
require 'psych'

module AiNotebookPrivateCopy
  module_function
  ROOT = '/etc/openclash/core/'
  GROUP = '__AI_NOTEBOOK_PROBE_ONLY__'
  INBOUND = 'ai-notebook-probe-only'
  PORT = 17_881
  MAX = 20_000_000
  LEAVES = %w[ss socks5 http vmess vless trojan hysteria2 hysteria tuic wireguard snell ssh mieru].freeze

  def locate
    found = []
    Dir['/proc/[0-9]*/cmdline'].each do |file|
      begin
        pid = file.split('/')[2]
        next unless File.readlink("/proc/#{pid}/exe").start_with?(ROOT)
        argv = File.binread(file).split("\0")
        next if argv.any? { |x| %w[/tmp/openclash-ai- /tmp/openclash-probe- /tmp/oc-ai-].any? { |prefix| x.include?(prefix) } }
        cwd = File.readlink("/proc/#{pid}/cwd")
        fi = argv.index('-f')
        di = argv.index('-d')
        conf = (fi && argv[fi+1]) || argv.find { |x| x.start_with?('-f=') }&.split('=',2)&.last
        dir = (di && argv[di+1]) || argv.find { |x| x.start_with?('-d=') }&.split('=',2)&.last
        path = File.expand_path(conf || 'config.yaml', File.expand_path(dir || cwd, cwd))
        next unless File.file?(path) && File.size(path).between?(1, MAX)
        found << [pid,path]
      rescue StandardError
        next
      end
    end
    found.size == 1 ? found.first : nil
  end

  def gate(config)
    return 'HOLD_LAYOUT' unless config.is_a?(Hash)
    leaves, groups, listeners = config.values_at('proxies','proxy-groups','listeners')
    listeners ||= []
    return 'HOLD_LAYOUT' unless leaves.is_a?(Array) && !leaves.empty? &&
                                groups.is_a?(Array) && listeners.is_a?(Array)
    return 'HOLD_PROXY_PROVIDERS' if config['proxy-providers'].is_a?(Hash) && !config['proxy-providers'].empty?
    return 'HOLD_RULE_PROVIDERS' if config['rule-providers'].is_a?(Hash) && !config['rule-providers'].empty?
    return 'HOLD_SCRIPT_OR_EXTERNAL' if %w[script sub-rules external-ui-url geox-url].any? { |k| config.key?(k) }
    return 'HOLD_GEO_RESOURCES' if config['geodata-mode'] == true || config['geo-auto-update'] == true
    rules = config.fetch('rules', [])
    return 'HOLD_RULES_LAYOUT' unless rules.is_a?(Array) && rules.all? { |x| x.is_a?(String) }
    return 'HOLD_GEO_RESOURCES' if rules.any? { |x| x.match?(/\A(?:GEOIP|GEOSITE|RULE-SET),/i) }
    names=[]
    leaves.each do |p|
      return 'HOLD_LEAF_LAYOUT' unless p.is_a?(Hash) && p['name'].is_a?(String) && LEAVES.include?(p['type'])
      names << p['name']
    end
    return 'HOLD_DUPLICATE_LEAF' unless names.uniq == names
    gnames=[]
    groups.each do |g|
      return 'HOLD_GROUP_LAYOUT' unless g.is_a?(Hash) && g['name'].is_a?(String) && g['proxies'].is_a?(Array)
      gnames << g['name']
    end
    return 'HOLD_NAME_COLLISION' unless gnames.uniq == gnames && (names & gnames).empty? &&
                                        !gnames.include?(GROUP) && !names.include?(GROUP)
    return 'HOLD_AI_PARENT' unless groups.count { |g| g['name']=='🤖 AI' && g['type']=='select' } == 1
    return 'HOLD_LISTENERS' unless listeners.all? { |x| x.is_a?(Hash) && x['name'].is_a?(String) &&
                                                       x['port'].to_s.match?(/\A\d+\z/) }
    return 'HOLD_LISTENER_COLLISION' if listeners.any? { |x| x['name']==INBOUND || x['port'].to_i==PORT }
    %w[port mixed-port socks-port redir-port tproxy-port].each do |k|
      next unless config.key?(k)
      return 'HOLD_PORT' unless config[k].to_s.match?(/\A\d+\z/) && config[k].to_i != PORT
    end
    'READY_FOR_PRIVATE_COPY_ONLY'
  rescue StandardError
    'HOLD_GATE_RUNTIME'
  end

  def overlay(config)
    verdict = gate(config)
    return [nil,verdict] unless verdict == 'READY_FOR_PRIVATE_COPY_ONLY'
    before = Marshal.load(Marshal.dump(config))
    after = Marshal.load(Marshal.dump(config))
    after['proxy-groups'] << { 'name'=>GROUP, 'type'=>'select',
                                'proxies'=>['REJECT', *before['proxies'].map { |x| x['name'] }] }
    after['listeners'] ||= []
    after['listeners'] << { 'name'=>INBOUND, 'type'=>'http',
                             'listen'=>'127.0.0.1', 'port'=>PORT, 'proxy'=>GROUP }
    return [nil,'HOLD_SOURCE_CHANGED'] unless config == before &&
      after['proxy-groups'][0...-1] == before['proxy-groups'] &&
      after['listeners'][0...-1] == before.fetch('listeners',[])
    [after,'PRIVATE_COPY_CANDIDATE']
  rescue StandardError
    [nil,'HOLD_COPY_RUNTIME']
  end

  def folder
    3.times do
      id = File.binread('/dev/urandom',8).unpack('H*').first
      path = "/tmp/ai_private_copy_#{id}"
      begin
        Dir.mkdir(path,0700)
        return path
      rescue Errno::EEXIST
        next
      end
    end
    nil
  end

  def remove_folder(path)
    return false unless path.is_a?(String) &&
      path.match?(%r{\A/tmp/ai_private_copy_[0-9a-f]{16}\z}) &&
      File.directory?(path) && !File.symlink?(path)
    erase = lambda do |dir|
      Dir.entries(dir).each do |name|
        next if name=='.' || name=='..'
        f="#{dir}/#{name}"
        if File.symlink?(f) || File.file?(f)
          File.delete(f)
        elsif File.directory?(f)
          erase.call(f)
          Dir.rmdir(f)
        else
          raise IOError
        end
      end
    end
    erase.call(path)
    Dir.rmdir(path)
    true
  rescue StandardError
    false
  end

  def native_test(exe,dir,config,seconds:12.0)
    child=nil
    begin
      child=Process.spawn(exe,'-t','-d',dir,'-f',config,out:File::NULL,err:File::NULL)
      deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+seconds
      loop do
        done,status=Process.waitpid2(child,Process::WNOHANG)
        if done
          child=nil
          return status.success? ? 'PRIVATE_COPY_SYNTAX_PASS' : 'HOLD_NATIVE_SYNTAX_REJECTED'
        end
        return 'HOLD_NATIVE_TIMEOUT' if Process.clock_gettime(Process::CLOCK_MONOTONIC)>=deadline
        sleep 0.1
      end
    rescue StandardError
      'HOLD_NATIVE_RUNTIME'
    ensure
      if child
        begin
          Process.kill('KILL',child)
          Process.waitpid(child)
        rescue Errno::ESRCH,Errno::ECHILD
        end
      end
    end
  end

  def run
    puts 'PRIVATE_COPY_GATE=START SOURCE_READ_ONLY=YES'
    located=locate
    unless located
      puts 'PRIVATE_COPY_RESULT=HOLD_CORE_NOT_UNIQUE'
      puts 'PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
      return
    end
    pid, source=located
    config=Psych.safe_load(File.binread(source,MAX+1),aliases:false)
    candidate,status=overlay(config)
    if candidate.nil?
      puts "PRIVATE_COPY_RESULT=#{status}"
      puts 'PRIVATE_COPY_TEST=NOT_RUN PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
      return
    end
    tmp=nil
    status='HOLD_PRIVATE_TMP'
    cleaned='YES'
    begin
      tmp=folder
      if tmp
        serialized=Psych.dump(candidate)
        if Psych.safe_load(serialized,aliases:false) != candidate
          status='HOLD_ROUNDTRIP'
        else
          target="#{tmp}/config.yaml"
          File.open(target,File::WRONLY|File::CREAT|File::EXCL,0600) { |f| f.write(serialized) }
          status=native_test("/proc/#{pid}/exe",tmp,target)
        end
      end
    rescue StandardError
      status='HOLD_PRIVATE_RUNTIME'
    ensure
      if tmp && !remove_folder(tmp)
        status='HOLD_PRIVATE_CLEANUP'
        cleaned='FAILED'
      end
    end
    puts "PRIVATE_COPY_RESULT=#{status}"
    puts "TEMP_CLEANUP=#{cleaned}"
    puts 'SOURCE_CREDENTIALS=LOCAL_ONLY RUNTIME_REJECT=UNVERIFIED'
    puts 'PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  rescue StandardError
    puts 'PRIVATE_COPY_RESULT=HOLD_READ_ONLY_RUNTIME'
    puts 'PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  end
end

AiNotebookPrivateCopy.run if __FILE__==$PROGRAM_NAME
