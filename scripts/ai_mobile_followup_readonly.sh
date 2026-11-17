umask 077
ruby -rpsych <<'RUBY'
# encoding: UTF-8
# Minimal one-shot follow-up to the confirmed 22:46 API GET. READ ONLY.
# Prints only fixed status labels and numeric counts, never names, paths,
# endpoint addresses, credentials, log lines or raw API/config documents.
module AiMobileFollowup
  module_function
  GROUPS=%w[Selector URLTest Fallback LoadBalance].freeze
  BUILTINS=%w[DIRECT REJECT REJECT-DROP PASS COMPATIBLE GLOBAL].freeze

  def source
    v=IO.popen(['uci','-q','get','openclash.config.config_path'],err:File::NULL){|io| io.read.to_s.strip}
    root='/etc/openclash/config/'
    p=File.expand_path(v.start_with?('/') ? v : File.join(root,v))
    return nil if v.empty? || !p.start_with?(root) || !File.file?(p)
    return nil unless File.realpath(p).start_with?(root) && File.size(p).between?(1,20_000_000)
    p
  rescue StandardError
    nil
  end

  def flag(args,key)
    i=args.index(key)
    return args[i+1] if i && i+1<args.size
    args.find{|s|s.start_with?(key+'=')}&.split('=',2)&.last
  end

  def one_core
    cores=[]
    Dir['/proc/[0-9]*/cmdline'].each do |f|
      begin
        pid=f.split('/')[2]
        exe=File.readlink("/proc/#{pid}/exe")
        next unless exe.start_with?('/etc/openclash/core/')
        args=File.binread(f).split("\0")
        next if args.any?{|a| a.include?('/tmp/openclash-ai-')||a.include?('/tmp/openclash-probe-')||a.include?('/tmp/oc-ai-')}
        cwd=File.readlink("/proc/#{pid}/cwd")
        d=File.expand_path(flag(args,'-d')||cwd,cwd)
        conf=File.expand_path(flag(args,'-f')||'config.yaml',d)
        next unless File.file?(conf)&&File.size(conf).between?(1,20_000_000)
        cores<<[pid,args,conf]
      rescue StandardError
        next
      end
    end
    cores.size==1 ? cores.first : nil
  end

  def core_clock_status(pid)
    stat=File.read("/proc/#{pid}/stat")
    parts=stat.split(') ',2)
    return 'PROC_STAT_PARSE_FAILED' unless parts.length==2
    tail=parts[1].split
    return 'PROC_STAT_PARSE_FAILED' unless tail.length>19
    ticks=Integer(tail[19])
    uptime=Float(File.read('/proc/uptime').split.first)
    return 'PROC_TIME_INVALID' unless ticks>=0 && uptime>0
    value=begin
      IO.popen(['getconf','CLK_TCK'],err:File::NULL){|io| io.read.to_s.strip}
    rescue Errno::ENOENT
      ''
    end
    return 'GETCONF_UNAVAILABLE' unless value.match?(/\A[1-9][0-9]*\z/)
    hz=value.to_i
    return 'HZ_INVALID' unless hz.between?(10,10000)
    started=Time.at(Time.now.to_f-uptime+ticks.to_f/hz)
    return 'CLOCK_INCONSISTENT' if started.to_f>Time.now.to_f+3
    'CORE_START_CALCULATED'
  rescue ArgumentError, RangeError, IndexError, TypeError
    'PROC_TIME_PARSE_FAILED'
  rescue StandardError
    'CORE_TIME_UNAVAILABLE'
  end

  def local_port(s)
    m=/\A(?:127\.0\.0\.1|0\.0\.0\.0):([0-9]{1,5})\z/.match(s.to_s)
    p=m&&m[1].to_i
    p if p && p.between?(1,65535)
  end

  def owns?(pid,port)
    inodes=%w[/proc/net/tcp /proc/net/tcp6].flat_map do |path|
      next [] unless File.file?(path)
      File.foreach(path).drop(1).filter_map do |line|
        c=line.split
        next unless c.length>9 && c[3]=='0A' && c[1].split(':').last.to_i(16)==port
        c[9]
      end
    end
    return false if inodes.empty?
    Dir["/proc/#{pid}/fd/*"].any? do |f|
      begin
        inodes.include?(File.readlink(f)[/\Asocket:\[(\d+)\]\z/,1])
      rescue StandardError
        false
      end
    end
  rescue StandardError
    false
  end

  def api(secret,port)
    return nil unless secret.is_a?(String)&&secret.bytesize<=512&&!secret.match?(/[\x00-\x1f]/)
    args=['curl','-q','--noproxy','*','--silent','--fail','--connect-timeout','2',
          '--max-time','7','--max-filesize','3000000','--config','-',
          "http://127.0.0.1:#{port}/proxies"]
    payload=''
    IO.popen(args,'r+',err:File::NULL) do |io|
      unless secret.empty?
        escaped=secret.gsub(/[\\"]/) {|c| '\\'+c}
        io.write("header = \"Authorization: Bearer #{escaped}\"\n")
      end
      io.close_write
      payload=io.read(3_000_001)
    end
    return nil unless $?.success? && payload.bytesize.between?(2,3_000_000)
    Psych.safe_load(payload,aliases:false)
  rescue StandardError
    nil
  end

  def count_summary(expected,live)
    return nil unless expected.is_a?(Array)&&expected.all?{|p|p.is_a?(Hash)&&p['name'].is_a?(String)&&!p['name'].empty?}
    names=expected.map{|p|p['name']}
    return nil unless names.uniq.length==names.length
    return nil unless live.is_a?(Hash)&&live['proxies'].is_a?(Hash)
    proxies=live['proxies']
    return nil unless proxies.all?{|n,p|n.is_a?(String)&&p.is_a?(Hash)&&p['type'].is_a?(String)}
    leaf=proxies.reject{|name,v| GROUPS.include?(v['type'])||BUILTINS.include?(name)}
    extras=leaf.reject{|name,_|names.include?(name)}
    extra_direct=extras.values.count{|v|%w[Direct Reject].include?(v['type'])}
    {expected:names.length,present:(names & leaf.keys).length,extra:extras.length,
     extra_direct:extra_direct,extra_other:extras.length-extra_direct}
  end

  def run
    puts 'FOLLOWUP=START READ_ONLY=YES'
    core=one_core
    unless core
      puts 'FOLLOWUP=SAFE_HOLD_CORE_NOT_UNIQUE'
      return 0
    end
    pid,args,conf=core
    puts "CORE_TIME_STAGE=#{core_clock_status(pid)}"
    src=source
    unless src
      puts 'EXTRA_CATALOG=SAFE_HOLD_SOURCE_UNAVAILABLE'
      return 0
    end
    base=Psych.safe_load(File.binread(src),aliases:false)
    runtime=Psych.safe_load(File.binread(conf),aliases:false)
    unless base.is_a?(Hash)&&runtime.is_a?(Hash)&&base['proxies'].is_a?(Array)&&base['proxies']==runtime['proxies']
      puts 'EXTRA_CATALOG=SAFE_HOLD_DISK_DIFFERENT'
      return 0
    end
    if (base['proxy-providers'].is_a?(Hash)&&!base['proxy-providers'].empty?) ||
       (runtime['proxy-providers'].is_a?(Hash)&&!runtime['proxy-providers'].empty?)
      puts 'EXTRA_CATALOG=SAFE_HOLD_PROVIDERS_UNSUPPORTED'
      return 0
    end
    port=local_port(flag(args,'-ext-ctl')||runtime['external-controller'])
    unless port&&owns?(pid,port)
      puts 'EXTRA_CATALOG=SAFE_HOLD_LOCAL_SOCKET_NOT_VERIFIED'
      return 0
    end
    data=api(flag(args,'-secret')||runtime['secret']||'',port)
    sums=count_summary(base['proxies'],data)
    unless sums
      puts 'EXTRA_CATALOG=SAFE_HOLD_API_OR_SCHEMA'
      return 0
    end
    puts 'EXTRA_CATALOG=READ_ONLY_GET_COUNTED'
    puts "EXPECTED=#{sums[:expected]} PRESENT=#{sums[:present]} EXTRA_LEAF=#{sums[:extra]}"
    puts "EXTRA_TYPE_COUNTS=DIRECT_OR_REJECT:#{sums[:extra_direct]} OTHER:#{sums[:extra_other]}"
    puts 'LIVE_FULL_CREDENTIALS_MATCH=UNVERIFIED'
    puts 'REMOTE_UPDATE_AND_RELOAD=UNVERIFIED'
    0
  rescue StandardError
    puts 'FOLLOWUP=SAFE_HOLD_NO_PRIVATE_OUTPUT'
    0
  ensure
    puts 'FOLLOWUP=FINISHED PRODUCTION_WRITES=NONE AI_SWITCH=NONE'
  end
end
exit AiMobileFollowup.run
RUBY
