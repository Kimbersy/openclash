# frozen_string_literal: true
require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require_relative '../scripts/ai_refresh_passive_observer_candidate'

class AiRefreshUnattendedControlCandidateTests < Minitest::Test
  G=AiRefreshPassiveObserverCandidate
  BOOT='00000000-1111-2222-3333-444444444444'

  def with_private_paths
    Dir.mktmpdir('ai-refresh-control-test') do |dir|
      keys=%i[SESSION_CONTROL SESSION_STATE SESSION_RECEIPT]
      original=keys.to_h{|key|[key,G.const_get(key)]}
      keys.each do |key|
        G.send(:remove_const,key)
        G.const_set(key,File.join(dir,key.to_s.downcase))
      end
      begin
        yield dir
      ensure
        keys.each do |key|
          G.send(:remove_const,key)
          G.const_set(key,original[key])
        end
      end
    end
  end

  def capture
    old=$stdout
    stream=StringIO.new
    $stdout=stream
    yield
    stream.string
  ensure
    $stdout=old
  end

  def test_strict_state_parser_rejects_extra_duplicate_unsafe_and_time_budget
    raw="PID=321\nSTART=9999\nBOOT=#{BOOT}\nDURATION=7200\nINTERVAL=120\n"
    s=G.parse_state(raw)
    assert_equal 321,s[:pid]
    assert_equal 9999,s[:start].to_i
    assert_equal 7200,s[:duration]
    assert_nil G.parse_state(raw+"URL=https://secret.invalid\n")
    assert_nil G.parse_state(raw+"PID=999\n")
    assert_nil G.parse_state(raw.sub('DURATION=7200','DURATION=10'))
    assert_nil G.parse_state(raw.sub('INTERVAL=120','INTERVAL=2'))
    assert_nil G.parse_state(raw.sub("BOOT=#{BOOT}","BOOT=private credential"))
    assert_nil G.parse_state(raw.sub('PID=321','PID=-1'))
    assert_nil G.parse_state('PID=321')
  end

  def test_missing_state_and_receipt_are_safe
    with_private_paths do
      output=capture { G.unattended_status }
      assert_includes output,'UNATTENDED_SESSION=ABSENT'
      assert_includes output,'UNATTENDED_RECEIPT=NOT_PRESENT'
      assert_includes output,'ALLOW_RECONCILE=NO ALLOW_SWITCH=NO'
      refute_includes output,'https:'
      assert File.file?(G::SESSION_CONTROL)
      assert_equal 0,(File.stat(G::SESSION_CONTROL).mode & 0o077)
    end
  end

  def test_receipt_only_allowlisted_enum_escapes_and_never_raw_data
    with_private_paths do
      File.open(G::SESSION_RECEIPT,'w',0600) do |f|
        f.puts 'BASELINE_SNAPSHOT=AVAILABLE ONLY_METADATA=YES'
        f.puts 'SECRET=private-password https://danger.invalid'
        f.puts 'PASSIVE_OBSERVER_RESULT=HOLD_NO_EVENT_BEFORE_DEADLINE'
      end
      assert_equal 'HOLD_NO_EVENT_BEFORE_DEADLINE',G.receipt_status
      File.open(G::SESSION_RECEIPT,'w',0600) do |f|
        f.puts 'PASSIVE_OBSERVER_RESULT=PASS_AI_ELIGIBLE'
      end
      assert_equal 'HOLD_RECEIPT_INVALID',G.receipt_status
      File.open(G::SESSION_RECEIPT,'w',0600) do |f|
        2.times{f.puts 'PASSIVE_OBSERVER_RESULT=HOLD_NO_EVENT_BEFORE_DEADLINE'}
      end
      assert_equal 'HOLD_RECEIPT_INCOMPLETE',G.receipt_status
    end
  end

  def test_symlink_and_world_readable_control_file_are_rejected
    with_private_paths do |dir|
      target=File.join(dir,'target')
      File.open(target,'w',0600){|f|f.puts 'safe'}
      File.symlink(target,G::SESSION_STATE)
      assert_nil G.read_state
      File.unlink(G::SESSION_STATE)
      File.open(G::SESSION_STATE,'w',0600){|f|f.puts 'state'}
      File.chmod(0644,G::SESSION_STATE)
      assert_nil G.read_state
      assert_includes capture{G.unattended_cleanup},'HOLD_SESSION_NOT_PROVEN_EXITED'
    end
  end

  def test_stop_never_sends_term_without_matching_pid_and_start
    with_private_paths do
      raw="PID=#{Process.pid}\nSTART=333\nBOOT=#{BOOT}\nDURATION=7200\nINTERVAL=120\n"
      File.open(G::SESSION_STATE,'w',0600){|f|f.write(raw)}
      out=capture do
        G.stub(:boot_id,BOOT) do
          G.stub(:pid_start,'333') do
            G.stub(:pid_cmd_matches?,false) do
              G.unattended_stop
            end
          end
        end
      end
      assert_includes out,'UNATTENDED_STOP=HOLD_NOT_AUTHENTICATED'
      assert File.file?(G::SESSION_STATE)
    end
  end

  def test_liveness_requires_boot_start_command_and_non_zombie
    s={pid:Process.pid,start:'444',boot:BOOT,duration:300,interval:60}
    G.stub(:boot_id,BOOT) do
      G.stub(:pid_start,'444') do
        G.stub(:pid_cmd_matches?,true) do
          G.stub(:pid_process_state,'S') do
            assert_equal 'RUNNING',G.state_liveness(s)
          end
          G.stub(:pid_process_state,'Z') do
            assert_equal 'EXITED',G.state_liveness(s)
          end
        end
        G.stub(:pid_cmd_matches?,false) do
          assert_equal 'HOLD_PID_IDENTITY_MISMATCH',G.state_liveness(s)
        end
      end
      G.stub(:pid_start,'445') do
        assert_equal 'HOLD_PID_IDENTITY_MISMATCH',G.state_liveness(s)
      end
    end
    G.stub(:boot_id,'99999999-1111-2222-3333-444444444444') do
      assert_equal 'HOLD_BOOT_CHANGED',G.state_liveness(s)
    end
  end

  def test_cleanup_only_private_state_and_receipt_when_proven_exited
    with_private_paths do
      File.open(G::SESSION_STATE,'w',0600){|f|f.write("PID=4\nSTART=11\nBOOT=#{BOOT}\nDURATION=300\nINTERVAL=60\n")}
      File.open(G::SESSION_RECEIPT,'w',0600){|f|f.puts('PASSIVE_OBSERVER_RESULT=HOLD_NO_EVENT_BEFORE_DEADLINE')}
      out=G.stub(:state_liveness,'EXITED'){capture {G.unattended_cleanup}}
      assert_includes out,'UNATTENDED_CLEANUP=PRIVATE_SESSION_FILES_REMOVED'
      refute File.exist?(G::SESSION_STATE)
      refute File.exist?(G::SESSION_RECEIPT)
      assert File.file?(G::SESSION_CONTROL) # NEVER unlink an active flock path.
    end
  end

  def test_detach_disarmed_by_default_and_fails_invalid_budget_without_fork
    source=File.expand_path('../scripts/ai_refresh_passive_observer_candidate.rb',__dir__)
    output=IO.popen(['ruby',source],err:File::NULL,&:read)
    assert_includes output,'HOLD_NOT_ARMED'
    assert_includes capture {G.unattended_detach(89,30)},'HOLD_INVALID_BUDGET'
    assert_includes capture {G.unattended_detach(300,1000)},'HOLD_INVALID_BUDGET'
  end

  def test_fork_detached_child_releases_control_lock_and_writes_final_receipt
    skip 'fork or setsid unavailable on CI host' unless Process.respond_to?(:fork) && Process.respond_to?(:setsid)
    with_private_paths do |dir|
      launch=File.join(dir,'start_output')
      saved=$stdout
      begin
        $stdout=File.open(launch,'w',0600)
        G.stub(:run,proc {|duration:,interval:|
          sleep 0.08
          G.report('HOLD_NO_EVENT_BEFORE_DEADLINE')
        }) do
          G.unattended_detach(300,60)
        end
      ensure
        $stdout.flush
        $stdout.close
        $stdout=saved
      end
      assert_includes File.read(launch),'UNATTENDED_START=START_SIGNAL_SENT_UNVERIFIED'
      80.times do
        break if G.receipt_status=='HOLD_NO_EVENT_BEFORE_DEADLINE'
        sleep 0.03
      end
      assert_equal 'HOLD_NO_EVENT_BEFORE_DEADLINE', G.receipt_status
      status=capture { G.unattended_status }
      # Child must NOT retain the parent control flock for its whole lifespan.
      refute_includes status,'HOLD_CONTROL_BUSY'
      assert_includes status,'ALLOW_RECONCILE=NO ALLOW_SWITCH=NO'
      assert_includes status,'UNATTENDED_RECEIPT='
      refute_includes status,'https:'
      80.times do
        break if G.state_liveness(G.read_state)=='EXITED'
        sleep 0.03
      end
      assert_equal 'EXITED', G.state_liveness(G.read_state)
      assert_includes capture{G.unattended_cleanup},'PRIVATE_SESSION_FILES_REMOVED'
    end
  end

  def test_no_unsafe_external_library_cron_procd_or_raw_receipt_release
    source=File.binread(File.expand_path('../scripts/ai_refresh_passive_observer_candidate.rb',__dir__))
    assert_empty source.scan(/^require ['"][^'"]+['"]$/)
    for fragment in ['--detach','--status','--stop','--cleanup','--schedule',
                     'Process.fork','Process.setsid','Process.kill', 'START=',
                     'File::NOFOLLOW','File::LOCK_EX|File::LOCK_NB',
                     'TRUSTED_REMOTE_COMMIT=NOT_VERIFIED',
                     'ALLOW_RECONCILE=NO ALLOW_SWITCH=NO',
                     'UNATTENDED_START=START_SIGNAL_SENT_UNVERIFIED']
      assert_includes source,fragment
    end
    refute_match(/Net::HTTP|curl|wget|https?:\/\/|system\(|require_relative|PUT \/proxies/,source)
    assert_includes source,'OUTPUT' if false
    refute_includes source,'crontab -'
  end
end
