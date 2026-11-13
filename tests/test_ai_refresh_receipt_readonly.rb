# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../scripts/ai_refresh_receipt_readonly'

class TestAiRefreshReceipt < Minitest::Test
  NOW = Time.local(2026, 11, 13, 21, 0, 0)

  def log(stamp, line)
    "#{stamp} [信息] #{line}\n"
  end

  def test_success_requires_start_then_named_completion
    s = log('2026-11-13 04:00:00', '开始更新配置文件〖Home〗...') +
        log('2026-11-13 04:00:20', '配置文件下载成功，使用内核测试是否有错误...') +
        log('2026-11-13 04:00:42', '配置文件〖Home〗更新成功！')
    result = AiRefreshReceipt.classified_log(s, alias_name:'Home', now:NOW)
    assert_equal 'LOG_REPORTED_UPDATED', result['result']
    assert_equal 'LT24H', result['age']
    assert result['completed']
  end

  def test_same_content_is_not_called_update
    s = log('2026-11-13 04:00:00','开始更新配置文件〖Home〗...') +
        log('2026-11-13 04:00:20','配置文件〖Home〗没有更新，停止继续操作!')
    assert_equal 'LOG_REPORTED_NO_CHANGE',
      AiRefreshReceipt.classified_log(s,alias_name:'Home',now:NOW)['result']
  end

  def test_newer_unfinished_attempt_wins_over_previous_success
    s = log('2026-11-13 03:00:00','开始更新配置文件〖Home〗...') +
        log('2026-11-13 03:00:10','配置文件〖Home〗更新成功！') +
        log('2026-11-13 20:00:00','开始更新配置文件〖Home〗...')
    assert_equal 'IN_PROGRESS',
      AiRefreshReceipt.classified_log(s,alias_name:'Home',now:NOW)['result']
  end

  def test_named_failure_is_not_success
    s = log('2026-11-13 04:00:00','开始更新配置文件〖Home〗...') +
        log('2026-11-13 04:00:10','配置文件〖Home〗更新失败！')
    assert_equal 'LOG_REPORTED_ERROR',
      AiRefreshReceipt.classified_log(s,alias_name:'Home',now:NOW)['result']
  end

  def test_fallback_failure_then_final_real_success
    s = log('2026-11-13 04:00:00','开始更新配置文件〖Home〗...') +
        log('2026-11-13 04:00:03','配置文件〖Home〗订阅失败，尝试不使用代理...') +
        log('2026-11-13 04:00:23','配置文件〖Home〗更新成功！')
    assert_equal 'LOG_REPORTED_UPDATED',
      AiRefreshReceipt.classified_log(s,alias_name:'Home',now:NOW)['result']
  end

  def test_unrelated_alias_does_not_validate_this_one
    s = log('2026-11-13 04:00:00','开始更新配置文件〖Other〗...') +
        log('2026-11-13 04:00:20','配置文件〖Other〗更新成功！')
    assert_equal 'NO_MATCHING_ATTEMPT',
      AiRefreshReceipt.classified_log(s,alias_name:'Home',now:NOW)['result']
  end

  def test_success_without_its_own_start_is_insufficient
    s = log('2026-11-13 04:00:20','配置文件〖Home〗更新成功！')
    assert_equal 'NO_MATCHING_ATTEMPT',
      AiRefreshReceipt.classified_log(s,alias_name:'Home',now:NOW)['result']
  end

  def test_stale_success_is_not_accepted_as_recent
    s = log('2026-11-10 04:00:00','开始更新配置文件〖Home〗...') +
        log('2026-11-10 04:00:20','配置文件〖Home〗更新成功！')
    assert_equal 'LOG_STALE',
      AiRefreshReceipt.classified_log(s,alias_name:'Home',now:NOW)['result']
  end

  def test_future_log_lines_not_admitted
    s = log('2026-11-14 04:00:00','开始更新配置文件〖Home〗...') +
        log('2026-11-14 04:00:20','配置文件〖Home〗更新成功！')
    assert_equal 'NO_MATCHING_ATTEMPT',
      AiRefreshReceipt.classified_log(s,alias_name:'Home',now:NOW)['result']
  end

  def test_unsafe_alias_rejected_without_logging_private_text
    for alias_name in ['Bad\nInjected', '', "evil\x00x"]
      assert_raises(ArgumentError) do
        AiRefreshReceipt.classified_log('',alias_name:alias_name,now:NOW)
      end
    end
  end
end
