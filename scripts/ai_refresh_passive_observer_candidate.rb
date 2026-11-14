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
  else
    AiRefreshPassiveObserverCandidate.report('HOLD_NOT_ARMED')
  end
end
