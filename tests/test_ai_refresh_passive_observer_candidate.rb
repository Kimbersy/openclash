# frozen_string_literal: true
require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require_relative '../scripts/ai_refresh_passive_observer_candidate'

class AiRefreshPassiveObserverCandidateTests < Minitest::Test
  G=AiRefreshPassiveObserverCandidate
  BOOT='00000000-1111-2222-3333-444444444444'

  def snapshot
    {boot:BOOT,core:['901','/etc/openclash/core/clash','net:[71]','300'],
     source:[1,101,900,1000,0,1000,0],
     runtime:[1,102,1000,1000,0,1000,0],
     log:[1,103,12,1000,0,1000,0]}
  end

  def changed
    b=Marshal.load(Marshal.dump(snapshot))
    b[:source]=[1,111,901,1001,0,1001,0]
    b[:runtime]=[1,112,1001,1001,0,1001,0]
    b[:core]=['902','/etc/openclash/core/clash','net:[71]','400']
    b
  end

  def test_even_perfect_sequence_only_observed_candidate
    a=snapshot
    b=changed
    assert_equal 'PASSIVE_POSTUPDATE_CHRONOLOGY_CANDIDATE_ONLY',
      G.classify(a,b,'SUCCESS_REPORTED',stable_samples:2)
    output=StringIO.new
    original=$stdout
    begin
      $stdout=output
      G.report('PASSIVE_POSTUPDATE_CHRONOLOGY_CANDIDATE_ONLY',a,b)
    ensure
      $stdout=original
    end
    s=output.string
    assert_includes s,'TRUSTED_REMOTE_COMMIT=NOT_VERIFIED'
    assert_includes s,'MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED'
    assert_includes s,'ALLOW_RECONCILE=NO ALLOW_SWITCH=NO'
    assert_includes s,'PRODUCTION_CONFIG=UNCHANGED'
    assert_includes s,'SOURCE_METADATA_CHANGED=YES'
    refute_includes s,'900' # no source inode
    refute_includes s,'clash'
  end

  def test_log_success_alone_never_becomes_commit
    assert_equal 'HOLD_LOG_HINT_NOT_COMMIT_PROOF',
      G.classify(snapshot,snapshot,'SUCCESS_REPORTED')
    assert_equal 'HOLD_NO_REFRESH_TRANSITION',
      G.classify(snapshot,snapshot,'NONE')
  end

  def test_source_or_runtime_alone_is_held
    a=snapshot
    b=changed
    b[:runtime]=a[:runtime]
    assert_equal 'HOLD_SOURCE_CHANGE_WITHOUT_COMMIT_PROOF',
      G.classify(a,b,'SUCCESS_REPORTED')
    b=changed
    b[:source]=a[:source]
    assert_equal 'HOLD_RUNTIME_CHANGE_WITHOUT_SOURCE_PROOF',
      G.classify(a,b,'NONE')
    b=changed
    b[:core]=a[:core]
    assert_equal 'HOLD_CORE_GENERATION_UNCORRELATED',
      G.classify(a,b,'SUCCESS_REPORTED')
  end

  def test_reboot_log_errors_overlap_and_unstable_samples_are_holds
    a=snapshot
    b=changed
    c=Marshal.load(Marshal.dump(b))
    c[:boot]='99999999-1111-2222-3333-444444444444'
    assert_equal 'HOLD_BOOT_CHANGED',G.classify(a,c,'SUCCESS_REPORTED')
    assert_equal 'HOLD_LOG_GAP',G.classify(a,b,'LOG_GAP')
    assert_equal 'HOLD_LOG_ERROR_HINT',G.classify(a,b,'ERROR_REPORTED')
    assert_equal 'HOLD_MULTIPLE_LOG_EVENTS',G.classify(a,b,'LOG_EVENTS_MIXED')
    assert_equal 'HOLD_UNSTABLE_OBSERVATION',G.classify(a,b,'SUCCESS_REPORTED',stable_samples:1)
    assert_equal 'HOLD_SNAPSHOT_UNAVAILABLE',G.classify(nil,b,'NONE')
  end

  def test_log_delta_only_anonymous_hint_never_leaks_alias
    Dir.mktmpdir do |d|
      path=File.join(d,'log')
      File.write(path,"INITIAL-LOG\n")
      a={log:G.stat_key(path,20_000)}
      File.open(path,'a'){|f|f.write("2026-11-14 21:00:00 [Info] Config File【SECRET_AIRPORT】Update Successful!\n")}
      b={log:G.stat_key(path,20_000)}
      assert_equal 'SUCCESS_REPORTED',G.log_hint(a,b,path)
      c={log:b[:log].dup}
      c[:log][1]+=1
      assert_equal 'LOG_GAP',G.log_hint(a,c,path)
      File.open(path,'a'){|f|f.write("2026-11-14 21:00:01 [Error] Config File【SECRET_AIRPORT】Update Error\n")}
      d2={log:G.stat_key(path,20_000)}
      assert_equal 'ERROR_REPORTED',G.log_hint(a,d2,path)
    end
  end

  def test_log_errors_and_gaps_are_sticky_and_never_overwritten_by_success
    assert_equal 'ERROR_REPORTED', G.merge_hint('ERROR_REPORTED','SUCCESS_REPORTED')
    assert_equal 'LOG_GAP', G.merge_hint('SUCCESS_REPORTED','LOG_GAP')
    assert_equal 'LOG_GAP', G.merge_hint('LOG_GAP','SUCCESS_REPORTED')
    assert_equal 'LOG_EVENTS_MIXED', G.merge_hint('SUCCESS_REPORTED','NO_CHANGE_REPORTED')
    assert_equal 'NO_CHANGE_REPORTED', G.merge_hint('NO_CHANGE_REPORTED','NONE')
    assert_equal 'ERROR_REPORTED', G.merge_hint('LOG_EVENTS_MIXED','ERROR_REPORTED')
    assert_equal 'HOLD_LOG_ERROR_HINT', G.classify(snapshot,changed,
      G.merge_hint('ERROR_REPORTED','SUCCESS_REPORTED'))
  end

  def test_same_size_log_rewrite_is_not_silent
    Dir.mktmpdir do |d|
      file=File.join(d,'log')
      File.binwrite(file,"SAME_LENGTH\n")
      base=G.stat_key(file,20_000)
      later=base.dup
      later[3]+=1 # changed mtime without a detectable byte-count change
      before={log:base}
      after={log:later}
      assert_equal 'LOG_GAP',G.log_hint(before,after,file)
      assert_equal 'NONE',G.log_hint(before,before,file)
      File.binwrite(file,"SHORT")
      now={log:G.stat_key(file,20_000)}
      assert_equal 'LOG_GAP',G.log_hint(before,now,file)
    end
  end

  def test_partial_appended_log_is_a_gap_not_authenticated_line
    Dir.mktmpdir do |d|
      file=File.join(d,'log')
      File.binwrite(file,"FIRST\n")
      a={log:G.stat_key(file,20_000)}
      File.open(file,'ab'){|f|f.write("2026-11-14 21:00:00 [Info] Config File SECRET Update Successful!")}
      b={log:G.stat_key(file,20_000)}
      assert_equal 'LOG_GAP',G.log_hint(a,b,file)
    end
  end

  def test_single_snapshot_probe_is_disarmed_no_observer_loop
    cmd=File.expand_path('../scripts/ai_refresh_passive_observer_candidate.rb',__dir__)
    out=IO.popen(['ruby',cmd,'--probe'],err:File::NULL,&:read)
    assert_includes out,'PASSIVE_OBSERVER=SNAPSHOT_PROBE ONCE=YES NO_HTTP=YES'
    assert_match(/PASSIVE_OBSERVER_RESULT=(BASELINE_SNAPSHOT_AVAILABLE_ONLY|HOLD_INITIAL_SNAPSHOT_UNAVAILABLE)/,out)
    assert_includes out,'TRUSTED_REMOTE_COMMIT=NOT_VERIFIED'
    assert_includes out,'ALLOW_RECONCILE=NO ALLOW_SWITCH=NO'
    assert_includes out,'LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
    refute_match(/https?:\/\/|SECRET_AIRPORT/,out)
  end

  def test_flock_second_instance_is_rejected_before_sampling
    lock=File.open(G::LOCK,File::RDWR|File::CREAT,0600)
    assert lock.flock(File::LOCK_EX|File::LOCK_NB)
    capture=StringIO.new
    old=$stdout
    begin
      $stdout=capture
      G.run(duration:90,interval:30)
    ensure
      $stdout=old
      lock.close
    end
    assert_includes capture.string,'PASSIVE_OBSERVER_RESULT=HOLD_ALREADY_RUNNING'
    assert_includes capture.string,'ALLOW_SWITCH=NO'
  end

  def test_no_implicit_arming_and_bounded_limits
    s=IO.popen(['ruby',File.expand_path('../scripts/ai_refresh_passive_observer_candidate.rb',__dir__)],err: File::NULL, &:read)
    assert_includes s,'HOLD_NOT_ARMED'
    capture=StringIO.new
    old=$stdout
    begin
      $stdout=capture
      G.run(duration:86_401,interval:30)
      G.run(duration:600,interval:10)
    ensure
      $stdout=old
    end
    assert_equal 2,capture.string.scan('HOLD_INVALID_BUDGET').length
  end

  def test_device_runtime_dependencies_and_no_http_or_secrets
    s=File.binread(File.expand_path('../scripts/ai_refresh_passive_observer_candidate.rb',__dir__))
    assert_empty s.scan(/^require ['"][^'"]+['"]$/)
    assert_includes s,"'uci','-q','get','openclash.config.config_path'"
    assert_includes s,'File::LOCK_EX|File::LOCK_NB'
    assert_includes s,"trap('TERM')"
    assert_includes s,"Process::CLOCK_MONOTONIC"
    assert_includes s,'MAX_SECONDS = 86_400'
    assert_includes s,"ARGV[0]=='--probe'"
    assert_includes s,'def merge_hint(old, current)'
    refute_match(/Net::HTTP|curl|wget|https?:\/\/|Process\.spawn|system\(|\.write\(|PUT \/proxies/,s)
  end
end
