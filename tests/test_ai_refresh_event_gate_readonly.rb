# frozen_string_literal: true
require 'minitest/autorun'
require 'time'
require_relative '../scripts/ai_refresh_event_gate_readonly'

class TestAiRefreshEventGate < Minitest::Test
  G = AiRefreshEventGate
  NOW = Time.local(2026, 11, 13, 21, 0, 0)
  HOUR = '4'
  ALIAS_NAME = 'TEST-SUB'

  def test_exact_cron_appointment_without_side_effects
    body = "0 4 * * * /usr/share/openclash/openclash.sh #openclash-cron-task\n"
    assert G.cron_matches?(body, '4', '*')
    assert G.cron_matches?(body, '04', '*')
    refute G.cron_matches?(body, '5', '*')
    refute G.cron_matches?("0 4 * * * curl http://private-token\n", '4', '*')
    refute G.cron_matches?(body, '4; command', '*')
    refute G.cron_matches?(body, '4', '1')
    assert G.cron_matches?("0 4 * * 2 /usr/share/openclash/openclash.sh\n", '4', '2')
  end

  def test_log_chinese_success_and_no_change_are_distinguished
    s = "2026-11-13 04:00:00 [信息] 配置文件〖TEST-SUB〗更新成功！\n"
    assert_equal 'RECENT_REPLACED_LOG_HINT', G.latest_event(s, ALIAS_NAME, NOW)
    c = "2026-11-13 05:00:00 [信息] 配置文件〖TEST-SUB〗没有更新，停止继续操作!\n"
    assert_equal 'RECENT_UNCHANGED_LOG_HINT', G.latest_event(s + c, ALIAS_NAME, NOW)
  end

  def test_english_log_and_newest_timestamp_not_log_order
    s = "2026-11-13 05:00:00 Config File〖TEST-SUB〗No Change, Do Nothing!\n"
    s += "2026-11-13 04:00:00 Config File〖TEST-SUB〗Update Successful!\n"
    assert_equal 'RECENT_UNCHANGED_LOG_HINT', G.latest_event(s, ALIAS_NAME, NOW)
  end

  def test_no_matching_alias_never_confirms_subscription_success
    other = "2026-11-13 04:00:00 配置文件〖OTHER〗更新成功！\n"
    assert_equal 'NOT_FOUND', G.latest_event(other, ALIAS_NAME, NOW)
    assert_equal 'UNAVAILABLE', G.latest_event(nil, ALIAS_NAME, NOW)
    assert_equal 'UNAVAILABLE', G.latest_event(other, '', NOW)
    assert_nil G.event_kind('secret', 'x' * 200)
  end

  def test_stale_or_future_or_unstamped_logs_fail_closed
    older = "2026-11-01 04:00:00 配置文件〖TEST-SUB〗更新成功！\n"
    assert_equal 'STALE', G.latest_event(older, ALIAS_NAME, NOW)
    future = "2026-11-16 04:00:00 配置文件〖TEST-SUB〗更新成功！\n"
    assert_equal 'NOT_FOUND', G.latest_event(future, ALIAS_NAME, NOW)
    unstamped = "配置文件〖TEST-SUB〗更新成功！\n"
    assert_equal 'NOT_FOUND', G.latest_event(unstamped, ALIAS_NAME, NOW)
    false_positive = "2026-11-13 04:00:00 Config File〖TEST-SUB〗Download Started..."
    assert_equal 'NOT_FOUND', G.latest_event(false_positive, ALIAS_NAME, NOW)
  end

  def test_alias_regular_expression_cannot_be_injected
    str = "2026-11-13 04:00:00 配置文件〖A.*B〗更新成功！"
    assert_equal 'NOT_FOUND', G.latest_event(str, 'ABC', NOW)
    assert_equal 'RECENT_REPLACED_LOG_HINT', G.latest_event(str, 'A.*B', NOW)
  end

  def test_gate_never_marks_memory_reload_as_pass
    args = {sched: 'ENABLED_DAILY', cron: 'MATCH', event: 'RECENT_REPLACED_LOG_HINT', disk: 'MATCH'}
    assert_equal 'BLOCK_CORE_MEMORY_UNVERIFIED', G.gate(**args)
    assert_equal 'BLOCK_SCHEDULE', G.gate(**args.merge(sched: 'OTHER'))
    assert_equal 'BLOCK_SCHEDULE', G.gate(**args.merge(cron: 'MISMATCH'))
    assert_equal 'BLOCK_REMOTE_EVENT', G.gate(**args.merge(event: 'STALE'))
    assert_equal 'BLOCK_REMOTE_EVENT', G.gate(**args.merge(event: 'UNAVAILABLE'))
    assert_equal 'BLOCK_DISK_MISMATCH', G.gate(**args.merge(disk: 'DIFFER'))
    assert_equal 'BLOCK_CORE_MEMORY_UNVERIFIED', G.gate(**args.merge(event: 'RECENT_UNCHANGED_LOG_HINT'))
  end

  def test_sensitive_logs_are_not_echoed
    data = +"2026-11-13 03:10:00 Config File〖TEST-SUB〗Downloading URL〖https://example.org?token=PRIVATE〗\n"
    data << "2026-11-13 04:00:00 Config File〖TEST-SUB〗Update Successful!\n"
    verdict = G.latest_event(data, ALIAS_NAME, NOW)
    assert_equal 'RECENT_REPLACED_LOG_HINT', verdict
    refute_match(/PRIVATE|example\.org|TEST-SUB/, verdict)
  end
end
