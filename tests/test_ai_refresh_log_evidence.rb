# frozen_string_literal: true
require 'minitest/autorun'
require 'time'
require_relative '../scripts/ai_refresh_log_evidence'

class TestAiRefreshLogEvidence < Minitest::Test
  NOW = Time.local(2026, 11, 13, 20, 55, 0)

  def line(when_at, msg, level: 'Info')
    "#{when_at.strftime('%Y-%m-%d %H:%M:%S')} [#{level}] #{msg}\n"
  end

  def test_actual_upstream_log_delimiters
    success = line(NOW - 70, 'Config File〖mine〗Update Successful!')
    unchanged = line(NOW - 60, 'Config File〖mine〗No Change, Do Nothing!')
    failed = line(NOW - 40, '〖mine〗Update Error, Please Try Again Later...', level: 'Error')
    assert_equal 'SUCCESS_REPORTED', AiRefreshLogEvidence.classify(success, 'mine', now: NOW)['status']
    assert_equal 'NO_CHANGE_REPORTED', AiRefreshLogEvidence.classify(unchanged, 'mine', now: NOW)['status']
    assert_equal 'ERROR_REPORTED', AiRefreshLogEvidence.classify(success + failed, 'mine', now: NOW)['status']
  end

  def test_exact_subscription_alias_and_update_success_is_not_remote_proof
    log = line(NOW - 70, 'Config File【mine】Update Successful!')
    r = AiRefreshLogEvidence.classify(log, 'mine', now: NOW)
    assert_equal 'SUCCESS_REPORTED', r['status']
    assert_equal 'LT1H', r['age']
    assert_equal 'NO_MATCH', AiRefreshLogEvidence.classify(log, 'other', now: NOW)['status']
  end

  def test_no_change_is_not_new_download
    log = line(NOW - 60, 'Config File【mine】No Change, Do Nothing!')
    assert_equal 'NO_CHANGE_REPORTED', AiRefreshLogEvidence.classify(log, 'mine', now: NOW)['status']
  end

  def test_latest_error_overrides_earlier_success
    log = line(NOW - 3600, 'Config File【mine】Update Successful!') +
          line(NOW - 20, '【mine】Update Error, Please Try Again Later...', level: 'Error')
    assert_equal 'ERROR_REPORTED', AiRefreshLogEvidence.classify(log, 'mine', now: NOW)['status']
  end

  def test_tied_error_overrides_success
    log = line(NOW - 30, 'Config File【mine】Update Successful!') +
          line(NOW - 30, '【mine】Update Error, Please Try Again Later...', level: 'Error')
    assert_equal 'ERROR_REPORTED', AiRefreshLogEvidence.classify(log, 'mine', now: NOW)['status']
  end

  def test_tied_success_and_no_change_are_ambiguous
    log = line(NOW - 30, 'Config File【mine】Update Successful!') +
          line(NOW - 30, 'Config File【mine】No Change, Do Nothing!')
    assert_equal 'AMBIGUOUS', AiRefreshLogEvidence.classify(log, 'mine', now: NOW)['status']
  end

  def test_old_or_future_events_are_not_current_evidence
    old = line(NOW - 3 * 86_400, 'Config File【mine】Update Successful!')
    future = line(NOW + 300, 'Config File【mine】Update Successful!')
    assert_equal 'STALE', AiRefreshLogEvidence.classify(old, 'mine', now: NOW)['status']
    assert_equal 'FUTURE_OR_BAD_CLOCK', AiRefreshLogEvidence.classify(future, 'mine', now: NOW)['status']
  end

  def test_unrelated_logs_or_raw_url_do_not_match
    log = line(NOW - 10, 'Downloading URL https://secret.example?token=SECRET') +
          line(NOW - 10, 'Config File【mine】Downloading User-Agent ...') +
          line(NOW - 10, 'Config File【other】Update Successful!')
    assert_equal 'NO_MATCH', AiRefreshLogEvidence.classify(log, 'mine', now: NOW)['status']
  end

  def test_bad_format_empty_alias_and_large_log_fail_closed
    assert_equal 'ALIAS_UNAVAILABLE', AiRefreshLogEvidence.classify('', '', now: NOW)['status']
    assert_equal 'NO_MATCH', AiRefreshLogEvidence.classify('not timestamp', 'mine', now: NOW)['status']
    assert_equal 'UNAVAILABLE', AiRefreshLogEvidence.classify('X' * (2_000_001), 'mine', now: NOW)['status']
    assert_equal 'UNAVAILABLE', AiRefreshLogEvidence.classify(nil, 'mine', now: NOW)['status']
  end

  def test_log_message_suffix_must_match_exact_expected_phrase
    log = line(NOW - 10, 'Config File【mine】Update Successful! but not really')
    assert_equal 'NO_MATCH', AiRefreshLogEvidence.classify(log, 'mine', now: NOW)['status']
  end
end
