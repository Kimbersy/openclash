#!/usr/bin/env ruby
# frozen_string_literal: true
# NOT INSTALLED. Ruby core only; no network, controller, config writes or reloads.
# Log/mtime/PID changes are HINTS, NEVER proof of a successful subscription.
module AiRefreshPassiveObserverCandidate
  module_function

  ROOT = '/etc/openclash/config/'
  LOG = '/tmp/openclash.log'
  LOCK = '/tmp/ai_refresh_passive_observer.lock'
  MAX_DELTA = 131_072
  MAX_SECONDS = 86_400

  def stat_key(path, max_size)
    a = File.stat(path)
    b = File.stat(path)
    return nil unless a.file? && a.size.between?(1,max_size)
    attrs = ->(s) {[s.dev,s.ino,s.size,s.mtime.to_i,s.mtime.nsec,s.ctime.to_i,s.ctime.nsec]}
    attrs.call(a) == attrs.call(b) ? attrs.call(a) : nil
  rescue StandardError
    nil
  end

  def selected_source
    v=IO.popen(['uci','-q','get','openclash.config.config_path'],err: File::NULL) { |io| io.read(1025).to_s.strip }
    return nil unless v && v.bytesize.between?(1,1024) && !v.match?(/[\x00-\x1f\x7f]/)
    name = File.expand_path(v.start_with?('/') ? v : File.join(ROOT,v))
    return nil unless name.start_with?(ROOT)
    real = File.realpath(name)
    real if real.start_with?(ROOT)
  rescue StandardError
    nil
  end

  def core_pid_start(raw)
    n=raw.rindex(')')
    return nil unless n
    value=raw[(n+1)..-1].split[19]
    value if value && value.match?(/\A\d+\z/)
  rescue StandardError
    nil
  end

  def flag(argv,opt)
    i=argv.index(opt)
    return argv[i+1] if i && i+1 < argv.length
    argv.find { |v| v.start_with?("#{opt}=") }&.split('=',2)&.last
  end

  def single_live_core
    found=[]
    Dir['/proc/[0-9]*/cmdline'].each do |f|
      begin
        pid=f.split('/')[2]
        exe=File.readlink("/proc/#{pid}/exe")
        next unless exe.start_with?('/etc/openclash/core/')
        argv=File.binread(f,16384).split("\0")
        next if argv.any? { |v| v.include?('/tmp/openclash-ai-') ||
          v.include?('/tmp/openclash-probe-') || v.include?('/tmp/oc-ai-') }
        cwd=File.readlink("/proc/#{pid}/cwd")
        home=File.expand_path(flag(argv,'-d') || cwd,cwd)
        cfg=File.expand_path(flag(argv,'-f') || 'config.yaml',home)
        start=core_pid_start(File.binread("/proc/#{pid}/stat",8192))
        ns=File.readlink("/proc/#{pid}/ns/net")
        found << [[pid,exe,ns,start],cfg] if start && File.file?(cfg)
      rescue StandardError
        next
      end
    end
    found.length == 1 ? found.first : nil
  end

  def snapshot
    source=selected_source
    core=single_live_core
    return nil unless source && core
    identity,config=core
    src=stat_key(source,20_000_000)
    runtime=stat_key(config,20_000_000)
    return nil if File.lstat(LOG).symlink?
    log=stat_key(LOG,50_000_000)
    boot=File.binread('/proc/sys/kernel/random/boot_id',128).strip
    return nil unless src && runtime && log && boot.match?(/\A[0-9a-f-]{36}\z/)
    return nil unless single_live_core == core
    {boot:boot,core:identity,source:src,runtime:runtime,log:log}
  rescue StandardError
    nil
  end

  def log_hint(before,after,path=LOG)
    a,b=before[:log],after[:log]
    return 'LOG_GAP' unless a && b && a[0..1] == b[0..1] && b[2]>=a[2]
    delta=b[2]-a[2]
    # Same size but changed timestamp means in-place rewrite/truncate+append.
    # Ordinary appended log at size==old must retain ALL metadata unchanged.
    if delta == 0
      return a == b ? 'NONE' : 'LOG_GAP'
    end
    return 'LOG_GAP' if delta>MAX_DELTA
    # Never follow a replaced log symlink; paths and raw log stay private.
    return 'LOG_GAP' if File.lstat(path).symlink?
    raw=File.open(path,'rb') do |f|
      st=f.stat
      return 'LOG_GAP' unless [st.dev,st.ino,st.size] == b[0..2]
      f.seek(a[2])
      f.read(delta)
    end
    return 'LOG_GAP' unless raw && raw.end_with?("\n")
    types=[]
    raw.to_s.each_line do |line|
      next unless line.start_with?('20') && line.include?('Config File')
      types << 'ERROR_REPORTED' if line.include?('Update Error') || line.include?('Subscribed Failed')
      types << 'SUCCESS_REPORTED' if line.include?('Update Successful!')
      types << 'NO_CHANGE_REPORTED' if line.include?('No Change, Do Nothing!')
    end
    return 'ERROR_REPORTED' if types.include?('ERROR_REPORTED')
    types.uniq.length>1 ? 'LOG_EVENTS_MIXED' : (types.first || 'NONE')
  rescue StandardError
    'LOG_GAP'
  end

  def merge_hint(old, current)
    # Safety-relevant gaps/errors are sticky. A later "success" log does not
    # repair an earlier unreadable or failed update interval.
    return 'LOG_GAP' if [old,current].include?('LOG_GAP')
    return 'ERROR_REPORTED' if [old,current].include?('ERROR_REPORTED')
    return 'LOG_EVENTS_MIXED' if [old,current].include?('LOG_EVENTS_MIXED')
    return old if current == 'NONE'
    return current if old == 'NONE'
    old == current ? old : 'LOG_EVENTS_MIXED'
  end

  def classify(before,after,hint,stable_samples:2)
    return 'HOLD_SNAPSHOT_UNAVAILABLE' unless before.is_a?(Hash) && after.is_a?(Hash)
    return 'HOLD_BOOT_CHANGED' unless before[:boot]==after[:boot]
    return 'HOLD_LOG_GAP' if hint=='LOG_GAP'
    return 'HOLD_LOG_ERROR_HINT' if hint=='ERROR_REPORTED'
    return 'HOLD_MULTIPLE_LOG_EVENTS' if hint=='LOG_EVENTS_MIXED'
    return 'HOLD_UNSTABLE_OBSERVATION' unless stable_samples.is_a?(Integer) && stable_samples>=2
    src=before[:source]!=after[:source]
    runtime=before[:runtime]!=after[:runtime]
    core=before[:core]!=after[:core]
    return 'HOLD_SOURCE_CHANGE_WITHOUT_COMMIT_PROOF' if src && !runtime
    return 'HOLD_RUNTIME_CHANGE_WITHOUT_SOURCE_PROOF' if runtime && !src
    return 'HOLD_LOG_HINT_NOT_COMMIT_PROOF' if hint!='NONE' && !src
    return 'HOLD_NO_REFRESH_TRANSITION' unless src || runtime || core
    return 'HOLD_CORE_GENERATION_UNCORRELATED' unless core
    # Purely observed chronology; never a protected update event/credential attestation.
    'PASSIVE_POSTUPDATE_CHRONOLOGY_CANDIDATE_ONLY'
  end

  def report(status,a=nil,b=nil)
    puts "PASSIVE_OBSERVER_RESULT=#{status}"
    if a && b
      puts "SOURCE_METADATA_CHANGED=#{a[:source]==b[:source] ? 'NO' : 'YES'}"
      puts "RUNTIME_FILE_METADATA_CHANGED=#{a[:runtime]==b[:runtime] ? 'NO' : 'YES'}"
      puts "CORE_IDENTITY_CHANGED=#{a[:core]==b[:core] ? 'NO' : 'YES'}"
    end
    puts 'TRUSTED_REMOTE_COMMIT=NOT_VERIFIED'
    puts 'MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED'
    puts 'ALLOW_RECONCILE=NO ALLOW_SWITCH=NO'
    puts 'PRIVATE_URLS_PATHS_NODES_AND_LOG_LINES=NOT_EMITTED'
    puts 'PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  end

  def probe
    puts 'PASSIVE_OBSERVER=SNAPSHOT_PROBE ONCE=YES NO_HTTP=YES'
    data = snapshot
    report(data ? 'BASELINE_SNAPSHOT_AVAILABLE_ONLY' : 'HOLD_INITIAL_SNAPSHOT_UNAVAILABLE')
  end

  # Unattended mode is a candidate only. No operator approval or target
  # Process.fork/setsid proof exists yet; never invoke --detach on production.
  SESSION_CONTROL = '/tmp/ai_refresh_passive_control.lock'
  SESSION_STATE = '/tmp/ai_refresh_passive_session.state'
  SESSION_RECEIPT = '/tmp/ai_refresh_passive_session.receipt'
  RECEIPT_MAX = 8192

  def private_open(path, flags, create: false)
    f = File.open(path, flags | File::NOFOLLOW, 0600)
    st = f.stat
    raise 'unsafe private file' unless st.file? && st.nlink == 1 &&
      st.uid == Process.uid && (st.mode & 0o077).zero? && st.size <= RECEIPT_MAX
    f
  rescue StandardError
    f&.close
    raise
  end

  def boot_id
    value=File.binread('/proc/sys/kernel/random/boot_id',128).strip
    value if value.match?(/\A[0-9a-f-]{36}\z/)
  rescue StandardError
    nil
  end

  def pid_start(pid)
    return nil unless pid.is_a?(Integer) && pid.positive?
    core_pid_start(File.binread("/proc/#{pid}/stat",8192))
  rescue StandardError
    nil
  end

  def pid_cmd_matches?(pid, duration, interval)
    argv=File.binread("/proc/#{pid}/cmdline",4096).split("\0")
    return false unless argv.include?('--detach')
    at=argv.index('--detach')
    argv[at+1]==duration.to_s && argv[at+2]==interval.to_s &&
      argv.length==at+3 && File.readlink("/proc/#{pid}/exe")==File.readlink('/proc/self/exe')
  rescue StandardError
    false
  end

  def parse_state(data)
    return nil unless data.is_a?(String) && data.bytesize.between?(1,512)
    items={}
    data.each_line do |line|
      key,value=line.strip.split('=',2)
      return nil unless %w[PID START BOOT DURATION INTERVAL].include?(key) &&
        !items.key?(key) && value && !value.empty?
      items[key]=value
    end
    return nil unless items.keys.sort==%w[BOOT DURATION INTERVAL PID START].sort
    return nil unless %w[PID START DURATION INTERVAL].all?{|k|items[k].match?(/\A[0-9]+\z/)}
    pid=items['PID'].to_i
    duration=items['DURATION'].to_i
    interval=items['INTERVAL'].to_i
    return nil unless pid.between?(1,4_194_304) &&
      duration.between?(300,MAX_SECONDS) && interval.between?(30,900) &&
      duration>=interval*3 && items['BOOT'].match?(/\A[0-9a-f-]{36}\z/)
    {pid:pid,start:items['START'],boot:items['BOOT'],duration:duration,interval:interval}
  end

  def read_state
    f=private_open(SESSION_STATE,File::RDONLY)
    raw=f.read(513)
    parse_state(raw)
  rescue Errno::ENOENT
    :absent
  rescue StandardError
    nil
  ensure
    f&.close
  end

  def pid_process_state(pid)
    raw=File.binread("/proc/#{pid}/stat",8192)
    pos=raw.rindex(')')
    return nil unless pos
    raw[(pos+1)..-1].strip.split.first
  rescue StandardError
    nil
  end

  def state_liveness(s)
    return 'ABSENT' if s==:absent
    return 'HOLD_STATE_UNTRUSTED' unless s.is_a?(Hash)
    return 'HOLD_BOOT_CHANGED' unless boot_id==s[:boot]
    begin
      Process.kill(0,s[:pid])
    rescue Errno::ESRCH
      return 'EXITED'
    rescue StandardError
      return 'HOLD_PID_UNAVAILABLE'
    end
    return 'HOLD_PID_IDENTITY_MISMATCH' unless pid_start(s[:pid])==s[:start] &&
      pid_cmd_matches?(s[:pid],s[:duration],s[:interval])
    return 'EXITED' if pid_process_state(s[:pid])=='Z'
    'RUNNING'
  end

  def receipt_status
    f=private_open(SESSION_RECEIPT,File::RDONLY)
    raw=f.read(RECEIPT_MAX+1)
    return 'HOLD_RECEIPT_OVERSIZED' if raw.bytesize>RECEIPT_MAX
    names=raw.lines.grep(/\APASSIVE_OBSERVER_RESULT=/)
    return 'HOLD_RECEIPT_INCOMPLETE' unless names.length==1
    name=names.first.strip.split('=',2).last
    return 'HOLD_RECEIPT_INVALID' unless name.match?(/\A(?:HOLD_[A-Z0-9_]+|STOPPED_BY_SIGNAL|PASSIVE_POSTUPDATE_CHRONOLOGY_CANDIDATE_ONLY)\z/)
    # Only an allowlisted enum escapes into the chat, never raw logs.
    name
  rescue Errno::ENOENT
    'HOLD_RECEIPT_MISSING'
  rescue StandardError
    'HOLD_RECEIPT_UNREADABLE'
  ensure
    f&.close
  end

  def with_control_lock
    lock=private_open(SESSION_CONTROL, File::RDWR|File::CREAT)
    @control_lock=lock
    unless lock.flock(File::LOCK_EX|File::LOCK_NB)
      puts 'UNATTENDED_CONTROL_RESULT=HOLD_CONTROL_BUSY'
      return
    end
    yield
  rescue StandardError
    puts 'UNATTENDED_CONTROL_RESULT=HOLD_CONTROL_UNAVAILABLE'
  ensure
    @control_lock=nil
    lock&.close
  end

  def schedule_plan
    # Upstream config-subscribe.lua defines auto_update_time as an hour 0..23.
    # No update trigger is called, and its actual execution remains unproven.
    values={}
    %w[auto_update config_auto_update_mode config_update_week_time auto_update_time].each do |key|
      values[key]=IO.popen(['uci','-q','get',"openclash.config.#{key}"],
                            err:File::NULL){|io|io.read(64).to_s.strip}
    end
    status=if values['auto_update']=='1' &&
      values['config_auto_update_mode']=='0' &&
      values['config_update_week_time']=='*' &&
      values['auto_update_time'].match?(/\A(?:[0-9]|1[0-9]|2[0-3])\z/)
      'DAILY_HOUR_DECLARED_ONLY'
    else
      'HOLD_SCHEDULE_UNKNOWN'
    end
    puts "SCHEDULE_RESULT=#{status}"
    puts "UCI_UPDATE_HOUR=#{status=='DAILY_HOUR_DECLARED_ONLY' ? format('%02d',values['auto_update_time'].to_i) : 'UNKNOWN'}"
    puts 'SCHEDULE_EXECUTION=NOT_VERIFIED TIMEZONE=DEVICE_LOCAL_UNCONFIRMED'
    puts 'PASSIVE_OBSERVER_INSTALLED=NO UPDATE_TRIGGERED=NO'
  rescue StandardError
    puts 'SCHEDULE_RESULT=HOLD_UCI_READ'
  end

  def unattended_status
    with_control_lock do
      s=read_state
      live=state_liveness(s)
      puts "UNATTENDED_SESSION=#{live}"
      receipt=s==:absent ? 'NOT_PRESENT' : (live=='RUNNING' ? 'RUNNING_NOT_FINAL' : receipt_status)
      puts "UNATTENDED_RECEIPT=#{receipt}"
      puts 'TRUSTED_REMOTE_COMMIT=NOT_VERIFIED MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED'
      puts 'ALLOW_RECONCILE=NO ALLOW_SWITCH=NO'
    end
  end

  def unattended_stop
    with_control_lock do
      s=read_state
      live=state_liveness(s)
      unless live=='RUNNING'
        puts "UNATTENDED_STOP=#{live == 'EXITED' ? 'ALREADY_EXITED' : 'HOLD_NOT_AUTHENTICATED'}"
        return
      end
      # Re-read identity immediately before sending a non-forceful signal;
      # never kill by pid alone, and never use KILL/killall.
      unless state_liveness(s)=='RUNNING'
        puts 'UNATTENDED_STOP=HOLD_PID_IDENTITY_CHANGED'
        return
      end
      Process.kill('TERM',s[:pid])
      puts 'UNATTENDED_STOP=TERM_SENT_NOT_CONFIRMED'
    end
  rescue StandardError
    puts 'UNATTENDED_STOP=HOLD_STOP_FAILED'
  end

  def unattended_cleanup
    with_control_lock do
      s=read_state
      unless state_liveness(s)=='EXITED'
        puts 'UNATTENDED_CLEANUP=HOLD_SESSION_NOT_PROVEN_EXITED'
        return
      end
      # SESSION_CONTROL lock is intentionally not unlinked.
      [SESSION_STATE,SESSION_RECEIPT].each do |path|
        f=private_open(path,File::RDONLY)
        f.close
      end
      [SESSION_STATE,SESSION_RECEIPT].each{|path|File.unlink(path)}
      puts 'UNATTENDED_CLEANUP=PRIVATE_SESSION_FILES_REMOVED'
    end
  rescue StandardError
    puts 'UNATTENDED_CLEANUP=HOLD_CLEANUP_FAILED'
  end

  def unattended_detach(duration,interval)
    unless duration.is_a?(Integer) && duration.between?(300,MAX_SECONDS) &&
      interval.is_a?(Integer) && interval.between?(30,900) && duration>=interval*3
      puts 'UNATTENDED_START=HOLD_INVALID_BUDGET'
      return
    end
    with_control_lock do
      unless read_state==:absent
        puts 'UNATTENDED_START=HOLD_EXISTING_SESSION_REQUIRES_REVIEW'
        return
      end
      boot=boot_id
      unless boot && Process.respond_to?(:fork) && Process.respond_to?(:setsid)
        puts 'UNATTENDED_START=HOLD_DETACH_CAPABILITY_UNKNOWN'
        return
      end
      state=nil
      output=nil
      begin
        output=private_open(SESSION_RECEIPT,File::RDWR|File::CREAT|File::EXCL)
        state=private_open(SESSION_STATE,File::RDWR|File::CREAT|File::EXCL)
        read_end,write_end=IO.pipe
        pid=Process.fork do
          begin
            # A fork inherits flock's open file description. Closing the
            # child's copy releases control access once the parent exits;
            # otherwise --status/--stop would remain blocked for hours.
            @control_lock&.close
            @control_lock=nil
            write_end.close
            ready=read_end.read(1)
            read_end.close
            exit!(1) unless ready=='1'
            Process.setsid
            $stdin.reopen('/dev/null','r')
            $stdout.reopen(output)
            output.close
            $stdout.sync=true
            $stderr.reopen('/dev/null','w')
            state.close
            run(duration:duration,interval:interval)
            $stdout.flush
            exit!(0)
          rescue StandardError
            begin
              $stdout.puts 'PASSIVE_OBSERVER_RESULT=HOLD_DETACHED_CHILD_RUNTIME'
              $stdout.flush
            rescue StandardError
            end
            exit!(2)
          end
        end
        read_end.close
        start=pid_start(pid)
        unless start
          write_end.close
          puts 'UNATTENDED_START=HOLD_CHILD_IDENTITY_UNAVAILABLE'
          return
        end
        payload="PID=#{pid}\nSTART=#{start}\nBOOT=#{boot}\nDURATION=#{duration}\nINTERVAL=#{interval}\n"
        state.write(payload)
        state.flush
        state.fsync
        write_end.write('1')
        write_end.close
        puts 'UNATTENDED_START=START_SIGNAL_SENT_UNVERIFIED'
        puts 'UNATTENDED_SESSION_FILES=PRIVATE_TMP_ONLY'
      ensure
        write_end&.close rescue nil
        read_end&.close rescue nil
        state&.close
        output&.close
      end
    end
  rescue StandardError
    puts 'UNATTENDED_START=HOLD_START_FAILED'
  end

  def run(duration:3600,interval:60)
    unless duration.is_a?(Integer) && duration.between?(90,MAX_SECONDS) &&
      interval.is_a?(Integer) && interval.between?(30,900) && duration>=interval*3
      report('HOLD_INVALID_BUDGET')
      return
    end
    # Dedicated /tmp flock path: never remove the path (avoids unlink lock race).
    # Refuse /tmp symlink tricks. Keep a 0600 root-owned regular lock only.
    lock=File.open(LOCK,File::RDWR|File::CREAT|File::NOFOLLOW,0600)
    meta=lock.stat
    unless meta.file? && meta.uid==Process.uid && meta.nlink==1 && (meta.mode & 0o077)==0
      report('HOLD_LOCK_PATH_UNSAFE')
      return
    end
    unless lock.flock(File::LOCK_EX|File::LOCK_NB)
      report('HOLD_ALREADY_RUNNING')
      return
    end
    stopped=false
    old_int=trap('INT'){stopped=true}
    old_term=trap('TERM'){stopped=true}
    old_hup=trap('HUP'){stopped=true}
    puts 'PASSIVE_OBSERVER=START NO_HTTP=YES PRODUCTION_READ_ONLY=YES'
    baseline=snapshot
    unless baseline
      report('HOLD_INITIAL_SNAPSHOT_UNAVAILABLE')
      return
    end
    puts 'BASELINE_SNAPSHOT=AVAILABLE ONLY_METADATA=YES'
    start=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    last=baseline
    hint='NONE'
    stable=0
    seen=false
    while !stopped && Process.clock_gettime(Process::CLOCK_MONOTONIC)-start<duration
      sleep interval
      break if stopped
      current=snapshot
      unless current
        report('HOLD_SAMPLE_UNAVAILABLE')
        return
      end
      new_hint=log_hint(last,current)
      hint=merge_hint(hint,new_hint)
      changed=[:source,:runtime,:core].any? { |key| baseline[key]!=current[key] }
      if changed || hint!='NONE'
        seen=true
        stable=[:source,:runtime,:core].all?{|key|last[key]==current[key]} ? stable+1 : 0
        if stable>=2
          report(classify(baseline,current,hint,stable_samples:stable),baseline,current)
          return
        end
      end
      last=current
    end
    report(stopped ? 'STOPPED_BY_SIGNAL' :
      seen ? 'HOLD_UNSTABLE_BEFORE_DEADLINE' : 'HOLD_NO_EVENT_BEFORE_DEADLINE')
  rescue StandardError
    report('HOLD_PASSIVE_OBSERVER_ERROR')
  ensure
    trap('INT',old_int) if defined?(old_int) && old_int
    trap('TERM',old_term) if defined?(old_term) && old_term
    trap('HUP',old_hup) if defined?(old_hup) && old_hup
    lock&.close
  end
end

if __FILE__==$PROGRAM_NAME
  # Default to disarmed: downloading/executing this file alone never watches.
  if ARGV.length==1 && ARGV[0]=='--probe'
    AiRefreshPassiveObserverCandidate.probe
  elsif ARGV.length==3 && ARGV[0]=='--observe' &&
    ARGV[1].match?(/\A\d+\z/) && ARGV[2].match?(/\A\d+\z/)
    AiRefreshPassiveObserverCandidate.run(duration:ARGV[1].to_i,interval:ARGV[2].to_i)
  elsif ARGV==['--schedule']
    AiRefreshPassiveObserverCandidate.schedule_plan
  elsif ARGV==['--status']
    AiRefreshPassiveObserverCandidate.unattended_status
  elsif ARGV==['--stop']
    AiRefreshPassiveObserverCandidate.unattended_stop
  elsif ARGV==['--cleanup']
    AiRefreshPassiveObserverCandidate.unattended_cleanup
  elsif ARGV.length==3 && ARGV[0]=='--detach' &&
    ARGV[1].match?(/\A\d+\z/) && ARGV[2].match?(/\A\d+\z/)
    # This path remains BLOCKED from router release until explicit approval
    # and separate device validation of fork/setsid/receipt lifecycle.
    AiRefreshPassiveObserverCandidate.unattended_detach(ARGV[1].to_i,ARGV[2].to_i)
  else
    AiRefreshPassiveObserverCandidate.report('HOLD_NOT_ARMED')
  end
end
