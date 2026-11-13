# frozen_string_literal: true
require 'minitest/autorun'
require 'tempfile'
require 'psych'
require_relative '../scripts/ai_refresh_activation_gate_readonly'
class TestAiRefreshActivationGate < Minitest::Test
  M = AiRefreshActivationGate
  NOW = Time.local(2026, 11, 13, 20, 55, 0)
  ALIAS_NAME = 'private-internal-config'
  def stamp(minutes=30)
    (NOW - minutes * 60).strftime('%Y-%m-%d %H:%M:%S')
  end
  def line(message, minutes=30)
    "#{stamp(minutes)} [Info] #{message}\n"
  end
  def oklog
    line("Config File【#{ALIAS_NAME}】Update Successful!")
  end
  def decision(log:oklog, **updates)
    args = {
      log:log, alias_name:ALIAS_NAME, now:NOW,
      source_mtime: NOW - 30*60 - 15,
      core_start_time: NOW - 29*60,
      source_disk_matches_runtime:true,
      single_source:true,
      runtime_core_count:1
    }.merge(updates)
    M.decision(**args)
  end
  def test_core_only_timestamp_parser_and_invalid_calendar_dates
    # Router only has Ruby core + Psych: Time.strptime is optional stdlib.
    good = M.parse_log_timestamp('2026-11-13 20:25:00')
    assert_instance_of Time, good
    assert_equal [2026, 11, 13, 20, 25, 0],
                 [good.year, good.month, good.day, good.hour, good.min, good.sec]
    assert_instance_of Time, M.parse_log_timestamp('2024-02-29 23:59:59')
    %w[2026-02-29 2026-04-31 2026-13-01 2026-11-13T20:25:00].each do |invalid|
      assert_nil M.parse_log_timestamp(invalid)
    end
    assert_nil M.parse_log_timestamp('2026-11-13 24:00:00')
    assert_nil M.parse_log_timestamp('2026-11-13 20:60:00')
    assert_nil M.parse_log_timestamp('2026-11-13 20:25:60')
    assert_equal 'NO_LOG_EVENT', decision(
      log: '2026-02-29 20:00:00 [Info] Config File【' + ALIAS_NAME + "】Update Successful!\n")
    refute_includes File.binread(File.expand_path('../scripts/ai_refresh_activation_gate_readonly.rb', __dir__)),
                    "require 'time'"
  end

  def test_missing_getconf_or_proc_is_safe_hold_not_an_exception
    assert_nil M.process_start(-999999)
    IO.stub(:popen, ->(*_args, **_kwargs) { raise Errno::ENOENT }) do
      assert_nil M.process_start(Process.pid)
    end
    assert_equal 'CORE_START_UNVERIFIED', decision(core_start_time:nil)
  end

  def test_upstream_actual_alias_guillemets
    log = line("Config File〖#{ALIAS_NAME}〗Update Successful!")
    assert_equal 'COLD_START_AFTER_UPDATE_CANDIDATE', decision(log: log)
    changed = line("Config File〖#{ALIAS_NAME}〗No Change, Do Nothing!")
    assert_equal 'NO_CONTENT_CHANGE', decision(log: changed)
  end

  def test_positive_startup_after_update_with_matching_disks_is_only_candidate
    assert_equal 'COLD_START_AFTER_UPDATE_CANDIDATE', decision
  end
  def test_failed_latest_event_overrides_older_success
    failed=line("Config File【#{ALIAS_NAME}】Subscribed Failed, Trying to Download Without Agent...", 10)
    assert_equal 'LATEST_UPDATE_FAILED', decision(log:oklog + failed)
    nochange=line("Config File【#{ALIAS_NAME}】No Change, Do Nothing!", 10)
    assert_equal 'NO_CONTENT_CHANGE', decision(log:oklog+nochange)
  end
  def test_missing_log_and_other_subscription_cannot_pass
    assert_equal 'NO_LOG_EVENT', decision(log:'')
    assert_equal 'NO_LOG_EVENT', decision(log:line('Config File【other】Update Successful!'))
    assert_equal 'NO_LOG_EVENT', decision(log:line('Config File【' + ALIAS_NAME + '】 Update Successful!'))
  end
  def test_old_and_future_evidence_block
    assert_equal 'LOG_STALE_OR_FUTURE', decision(log:line("Config File【#{ALIAS_NAME}】Update Successful!", 4300))
    assert_equal 'LOG_STALE_OR_FUTURE', decision(log:line("Config File【#{ALIAS_NAME}】Update Successful!", -1))
  end
  def test_mtime_and_core_process_start_constraints
    assert_equal 'SOURCE_CHANGED_AFTER_LOG', decision(source_mtime:NOW)
    assert_equal 'SOURCE_MTIME_TOO_OLD', decision(source_mtime:NOW-2600)
    assert_equal 'CORE_PREDATES_UPDATE', decision(core_start_time:NOW-31*60)
    assert_equal 'CORE_START_UNVERIFIED', decision(core_start_time:nil)
    assert_equal 'CLOCK_INCONSISTENT', decision(core_start_time:NOW+50)
  end
  def test_fail_closed_on_ambiguous_source_core_and_disk
    assert_equal 'SOURCE_NOT_UNIQUE', decision(single_source:false)
    assert_equal 'RUNTIME_AMBIGUOUS', decision(runtime_core_count:2)
    assert_equal 'DISK_DEFINITIONS_DIFFER', decision(source_disk_matches_runtime:false)
  end
  def test_never_echo_sensitive_identifiers
    log = "2026-11-13 20:00:00 [Info] Download URL https://airport.invalid/key=SECRET\n" + oklog
    assert_equal 'COLD_START_AFTER_UPDATE_CANDIDATE', decision(log:log)
    refute_includes decision(log:log), 'SECRET'
    refute_includes decision(log:log), ALIAS_NAME
  end
  def test_private_yamls_are_checked_in_memory_only
    a=Tempfile.create(['ai-a','.yaml'])
    b=Tempfile.create(['ai-b','.yaml'])
    begin
      a.write(Psych.dump({'proxies'=>[{'name'=>'node', 'password'=>'superprivate'}]}));a.flush
      b.write(Psych.dump({'proxies'=>[{'name'=>'node', 'password'=>'superprivate'}]}));b.flush
      assert M.definitions_match?(a.path,b.path)
      b.rewind;b.truncate(0);b.write(Psych.dump({'proxies'=>[{'name'=>'node','password'=>'different'}]}));b.flush
      refute M.definitions_match?(a.path,b.path)
    ensure
      a.close;b.close
    end
  end
end
