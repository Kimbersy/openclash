#!/bin/sh
# Read-only: classify active controller binding and verify socket ownership.
# Only loopback GET to a verified Mihomo-owned controller socket; no PUT, no secrets in output.
umask 077
ruby -rpsych <<'RUBY'
# encoding: UTF-8
begin
  def flag(args,key)
    i=args.index(key)
    return args[i+1] if i && args[i+1]
    x=args.find{|t| t.start_with?(key+'=')}
    x && x[(key.size+1)..-1]
  end
  runtime=nil
  Dir.glob('/proc/[0-9]*/cmdline').each do |entry|
    begin
      pid=entry.split('/')[2]
      exe=File.readlink("/proc/#{pid}/exe")
      next unless exe.start_with?('/etc/openclash/core/') || File.basename(exe).match?(/\A(?:clash_meta|mihomo)\z/)
      args=File.binread(entry).split("\0")
      next if args.any?{|a| a.include?('/tmp/openclash-probe-')}
      cwd=File.readlink("/proc/#{pid}/cwd")
      dir=File.expand_path(flag(args,'-d') || flag(args,'--dir') || cwd,cwd)
      conf=File.expand_path(flag(args,'-f') || flag(args,'--config') || 'config.yaml',dir)
      next unless File.file?(conf) && File.size(conf).between?(1,20_000_000)
      runtime=[pid,args,conf]
      break
    rescue StandardError
    end
  end
  unless runtime
    puts 'RUNTIME_CORE=NOT_LOCATED'; puts 'CONTROLLER_AUDIT=SKIPPED'; exit
  end
  pid,args,path=runtime
  cfg=Psych.safe_load(File.binread(path),aliases:false)
  raise unless cfg.is_a?(Hash)
  ctrl=(flag(args,'-ext-ctl') || cfg['external-controller']).to_s
  secret=(flag(args,'-secret') || cfg['secret']).to_s
  auth=secret.empty? ? 'EMPTY' : 'SET'
  pattern=/\A(0\.0\.0\.0|127\.0\.0\.1|localhost|\[::\]|\[::1\]|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+):([0-9]{1,5})\z/
  m=pattern.match(ctrl)
  host=m && m[1]
  port=m && m[2].to_i
  valid=m && port.between?(1,65535)
  scope=if ctrl.empty? then 'NOT_CONFIGURED'
    elsif !valid then 'OTHER_OR_UNSUPPORTED'
    elsif host=='0.0.0.0' then 'IPV4_ALL'
    elsif host=='127.0.0.1' || host=='localhost' then 'IPV4_LOOPBACK'
    elsif host=='[::]' then 'IPV6_ALL'
    elsif host=='[::1]' then 'IPV6_LOOPBACK'
    else 'IPV4_PRIVATE_ADDRESS'
    end
  puts "RUNTIME_CORE=FOUND CONTROLLER_BIND=#{scope} AUTH=#{auth}"
  unix=(cfg['external-controller-unix'].to_s.empty? ? 'NO' : 'CONFIGURED')
  tls=(cfg['external-controller-tls'].to_s.empty? ? 'NO' : 'CONFIGURED')
  puts "CONTROLLER_UNIX=#{unix} CONTROLLER_TLS=#{tls}"
  unless valid
    puts 'SOCKET_OWNED=UNKNOWN LOCAL_API_GET=SKIPPED'; exit
  end
  sock_inodes=[]
  %w[/proc/net/tcp /proc/net/tcp6].each do |netfile|
    next unless File.file?(netfile)
    File.readlines(netfile).drop(1).each do |line|
      c=line.split
      next unless c.size>9 && c[3]=='0A'
      next unless c[1].split(':').last.to_i(16)==port
      sock_inodes << c[9]
    end
  end
  owned=Dir.glob("/proc/#{pid}/fd/*").any? do |fd|
    begin
      sock_inodes.include?(File.readlink(fd)[/\Asocket:\[(\d+)\]\z/,1])
    rescue StandardError
      false
    end
  end
  puts "SOCKET_OWNED=#{owned ? 'YES' : 'NO_OR_UNVERIFIED'}"
  if !owned || !%w[IPV4_ALL IPV4_LOOPBACK].include?(scope) || auth!='SET'
    puts 'LOCAL_API_GET=SKIPPED_SAFETY'; exit
  end
  if secret.bytesize>512 || secret.match?(/[\r\n\x00-\x1f]/)
    puts 'LOCAL_API_GET=SKIPPED_SECRET_FORMAT'; exit
  end
  begin
    group='🤖 AI'
    path_part=group.bytes.map{|x| '%%%02X'%x}.join
    url="http://127.0.0.1:#{port}/proxies/#{path_part}"
    curlargs=['curl','-q','--noproxy','*','--silent','--show-error','--fail',
          '--connect-timeout','2','--max-time','5','--config','-',url]
    data=''
    IO.popen(curlargs,'r+',err:File::NULL) do |p|
      protected=secret.gsub(/[\\"]/){|c| '\\'+c}
      p.write("header = \"Authorization: Bearer #{protected}\"\n")
      p.close_write
      data=p.read(100_001)
    end
    raise 'invalid_response' if data.empty? || data.bytesize>100_000
    result=Psych.safe_load(data,aliases:false)
    raise 'not_a_group' unless result.is_a?(Hash) && result['name']==group && result['all'].is_a?(Array)
    members=result['all']
    chosen=result['now']
    refs=cfg['proxy-groups'].is_a?(Array) ? cfg['proxy-groups'].map{|g| g['name'] if g.is_a?(Hash)}.compact : []
    kind=chosen.nil? ? 'UNSET' : (refs.include?(chosen) ? 'GROUP' : (chosen=='DIRECT' ? 'DIRECT' : 'NODE_OR_OTHER'))
    type=result['type'].to_s
    type=type.match?(/selector|select/i) ? 'SELECT' : 'OTHER'
    puts "LOCAL_API_GET=PASS TYPE=#{type} MEMBERS=#{members.length} NOW_KIND=#{kind}"
  rescue StandardError
    puts 'LOCAL_API_GET=UNAVAILABLE_OR_UNPARSEABLE'
  end
rescue StandardError
  puts 'CONTROLLER_AUDIT=UNAVAILABLE_NO_SECRETS_EXPOSED'
end
RUBY
