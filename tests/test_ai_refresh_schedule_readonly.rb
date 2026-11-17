# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'psych'
require_relative '../scripts/ai_refresh_schedule_readonly'

class TestAiRefreshSchedule < Minitest::Test
  def test_appointment_daily_and_weekly
    h = {'auto_update'=>'1','config_auto_update_mode'=>'0',
         'config_update_week_time'=>'*','auto_update_time'=>'4'}
    assert_equal({'auto_update'=>'ENABLED','mode'=>'APPOINTMENT','schedule'=>'DAILY'}, AiRefreshSchedule.status(h))
    h['config_update_week_time']='5'
    assert_equal 'WEEKLY', AiRefreshSchedule.status(h)['schedule']
    h['config_update_week_time']='invalid'
    assert_equal 'UNKNOWN', AiRefreshSchedule.status(h)['schedule']
  end

  def test_loop_schedule_and_rejects_nonpositive_interval
    h={'auto_update'=>'1','config_auto_update_mode'=>'1','config_update_interval'=>'240'}
    assert_equal 'PERIODIC', AiRefreshSchedule.status(h)['schedule']
    h['config_update_interval']='0'
    assert_equal 'UNKNOWN', AiRefreshSchedule.status(h)['schedule']
    h['config_update_interval']='1;rm -rf /'
    assert_equal 'UNKNOWN', AiRefreshSchedule.status(h)['schedule']
  end

  def test_disabled_and_ambiguous_uci_cannot_claim_running
    assert_equal 'DISABLED', AiRefreshSchedule.status({'auto_update'=>'0'})['auto_update']
    assert_equal 'UNKNOWN', AiRefreshSchedule.status({})['auto_update']
  end

  def test_source_disk_versus_actual_reload_is_not_conflated
    Dir.mktmpdir do |dir|
      a=File.join(dir,'source.yaml')
      b=File.join(dir,'loaded.yaml')
      File.write(a, Psych.dump({'proxies'=>[{'name'=>'A','server'=>'private','password'=>'secret'}]}))
      File.write(b, Psych.dump({'proxies'=>[{'name'=>'A','server'=>'private','password'=>'secret'}]}))
      assert AiRefreshSchedule.disk_definitions_match?(a,b)
      File.write(b, Psych.dump({'proxies'=>[{'name'=>'A','server'=>'other','password'=>'secret'}]}))
      refute AiRefreshSchedule.disk_definitions_match?(a,b)
    end
  end

  def test_invalid_private_configs_fail_closed
    Dir.mktmpdir do |dir|
      a=File.join(dir,'data.yaml')
      File.write(a, Psych.dump({'no_proxies'=>'x'}))
      assert_raises(RuntimeError) { AiRefreshSchedule.disk_definitions_match?(a,a) }
    end
    assert_nil AiRefreshSchedule.safe_source_file('/tmp/untrusted-private.yaml')
  end

  def test_age_buckets
    n = Time.utc(2026,11,13)
    assert_equal 'FUTURE', AiRefreshSchedule.age_bucket(n+1,n)
    assert_equal 'LT24H', AiRefreshSchedule.age_bucket(n-3600,n)
    assert_equal 'LT7D', AiRefreshSchedule.age_bucket(n-172800,n)
    assert_equal 'OLDER', AiRefreshSchedule.age_bucket(n-777600,n)
  end
end
