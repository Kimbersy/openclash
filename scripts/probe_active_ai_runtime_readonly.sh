#!/bin/sh
# Read-only production OpenClash/Mihomo AI-group & controller safety audit.
# Never prints names, secrets, endpoints, IPs, or subscription contents.
umask 077
ruby -rpsych <<'RUBY'
# encoding: UTF-8
begin
  require 'psych'
  def flag(argv, name)
    i=argv.index(name)
    return argv[i+1] if i && argv[i+1]
    x=argv.find{|v| v.start_with?(name+'=')}
    x ? x[(name.size+1)..-1] : nil
  end
  def output_group(cfg)
    gs=cfg['proxy-groups']
    gs=[] unless gs.is_a?(Array)
    ai=gs.find{|x| x.is_a?(Hash) && x['name']=='🤖 AI'}
    if ai
      t=ai['type'].to_s.downcase
      t=%w[select fallback url-test load-balance].include?(t) ? t : 'OTHER'
      ms=ai['proxies'].is_a?(Array) ? ai['proxies'].size : 0
      puts "AI_GROUP=YES TYPE=#{t} CONFIGURED_MEMBERS=#{ms}"
    else
      puts 'AI_GROUP=NO_OR_DYNAMIC'
    end
    ai
  end
  found=nil
  Dir.glob('/proc/[0-9]*/cmdline').each do |cp|
    begin
      pid=cp.split('/')[2]
      exe=File.readlink("/proc/#{pid}/exe")
      next unless exe.include?('/etc/openclash/core/') || File.basename(exe).match?(/\A(?:clash_meta|mihomo)(?:\s|\z)/)
      argv=File.binread(cp).split("\0")
      next if argv.empty? || argv.join(' ').include?('/tmp/openclash-probe-')
      cwd=File.readlink("/proc/#{pid}/cwd")
      home=flag(argv,'-d') || flag(argv,'--dir') || cwd
      file=flag(argv,'-f') || flag(argv,'--config') || 'config.yaml'
      file=File.expand_path(file, home.start_with?('/') ? home : cwd)
      next unless File.file?(file) && File.size(file).between?(1,20_000_000)
      found=[pid,argv,file]
      break
    rescue StandardError, SystemCallError
      next
    end
  end
  if !found
    puts 'RUNTIME_CORE=NOT_LOCATED'
    puts 'RUNTIME_AI_GROUP=UNKNOWN'
    puts 'CONTROLLER=UNKNOWN API_READ=SKIPPED'
  else
    pid,argv,file=found
    puts 'RUNTIME_CORE=FOUND'
    cfg=Psych.safe_load(File.binread(file),aliases:false)
    raise 'nonmapping' unless cfg.is_a?(Hash)
    puts 'RUNTIME_CONFIG=READABLE'
    output_group(cfg)
    addr=flag(argv,'-ext-ctl') || cfg['external-controller']
    key=flag(argv,'-secret') || cfg['secret']
    key=key.to_s
    auth=key.empty? ? 'EMPTY' : 'SET'
    if addr.to_s.empty?
      puts "CONTROLLER=NOT_CONFIGURED AUTH=#{auth} API_READ=SKIPPED"
    elsif (match=/\A(?:127\.0\.0\.1|localhost|\[::1\]):([0-9]{1,5})\z/.match(addr.to_s)) && match[1].to_i.between?(1,65535)
      port=match[1].to_i
      puts "CONTROLLER=LOOPBACK AUTH=#{auth}"
      if !system('command -v curl >/dev/null 2>&1')
        puts 'API_READ=SKIPPED_NO_CURL'
      elsif !key.empty? && (key.bytesize>512 || key.match?(/[\r\n\x00-\x1f]/))
        puts 'API_READ=SKIPPED_UNSAFE_TOKEN_FORMAT'
      else
        begin
          name='🤖 AI'.bytes.map{|x| '%%%02X'%x}.join
          url="http://127.0.0.1:#{port}/proxies/#{name}"
          args=['curl','-q','--noproxy','*','-s','--connect-timeout','2','--max-time','5','--fail','--config','-',url]
          payload=''
          IO.popen(args,'r+',err:File::NULL) do |io|
            if !key.empty?
              esc=key.gsub(/[\\"]/){|c| '\\'+c}
              io.write("header = \"Authorization: Bearer #{esc}\"\n")
            end
            io.close_write
            payload=io.read(200_001)
          end
          raise 'bad payload' if payload.empty? || payload.bytesize>200_000
          data=Psych.safe_load(payload,aliases:false)
          raise 'not group' unless data.is_a?(Hash)
          members=data['all'].is_a?(Array) ? data['all'] : []
          now=data['now']
          t=data['type'].to_s
          t=t.match?(/selector|select/i) ? 'select' : (t.match?(/fallback|urltest|url-test/i) ? 'auto_group' : 'OTHER')
          other_groups=cfg['proxy-groups'].is_a?(Array) ? cfg['proxy-groups'].map{|g| g['name'] if g.is_a?(Hash)}.compact : []
          kind=now.nil? ? 'UNSET' : (other_groups.include?(now) ? 'GROUP' : (now=='DIRECT' ? 'DIRECT' : 'NODE_OR_OTHER'))
          puts "API_READ=PASS AI_RUNTIME_TYPE=#{t} AI_RUNTIME_MEMBERS=#{members.size} AI_NOW_KIND=#{kind}"
        rescue StandardError
          puts 'API_READ=UNAVAILABLE_OR_UNPARSEABLE'
        end
      end
    else
      puts "CONTROLLER=NON_LOOPBACK_OR_UNSUPPORTED AUTH=#{auth} API_READ=SKIPPED_SAFETY"
    end
  end
rescue StandardError
  puts 'RUNTIME_CHECK=UNAVAILABLE_NO_SECRETS_EXPOSED'
end
RUBY
