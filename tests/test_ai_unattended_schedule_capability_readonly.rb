# frozen_string_literal: true
require 'minitest/autorun'
require 'stringio'
require_relative '../scripts/ai_unattended_schedule_capability_readonly'

class AiUnattendedScheduleCapabilityReadOnlyTests < Minitest::Test
  G=AiUnattendedScheduleCapabilityReadOnly
  def values(hour)
    {'auto_update'=>'1','config_auto_update_mode'=>'0',
     'config_update_week_time'=>'*','auto_update_time'=>hour}
  end

  def test_daily_hour_only_from_explicit_uci_value
    (0..23).each do |hour|
      assert_equal ['DAILY_HOUR_DECLARED_ONLY',format('%02d',hour)],
                   G.classify(values(hour.to_s))
    end
  end

  def test_missing_or_invalid_hour_or_schedule_holds
    [nil,'','24','-1','1:00','04:00','4;secret','example.com'].each do |hour|
      assert_equal ['HOLD_UPDATE_HOUR_UNDECLARED','UNKNOWN'],G.classify(values(hour))
    end
    changes=[['auto_update','0'],['auto_update',nil],
             ['config_auto_update_mode','1'],['config_update_week_time','1']]
    changes.each do |key,value|
      input=values('4')
      input[key]=value
      assert_equal ['HOLD_SCHEDULE_NOT_DAILY','UNKNOWN'],G.classify(input)
    end
  end

  def test_target_output_no_background_activation_and_no_secrets
    out=IO.popen(['ruby',File.expand_path('../scripts/ai_unattended_schedule_capability_readonly.rb',__dir__)],
                 err:File::NULL,&:read)
    assert_includes out,'UNATTENDED_SCHEDULE_PREFLIGHT=START NO_HTTP=YES'
    assert_match(/SCHEDULE_RESULT=(HOLD_[A-Z_]+|DAILY_HOUR_DECLARED_ONLY)/,out)
    assert_match(/RUBY_FORK_METHOD=(PRESENT|NOT_PRESENT)/,out)
    assert_match(/RUBY_SETSID_METHOD=(PRESENT|NOT_PRESENT)/,out)
    assert_includes out,'DETACHED_SESSION=NOT_STARTED CRON_PROCD=UNCHANGED'
    assert_includes out,'AUTO_SWITCH=OFF'
    refute_match(/https?:\/\/|password|token=|airport-alias/i,out)
  end

  def test_zero_additional_dependencies_or_mutations
    s=File.read(File.expand_path('../scripts/ai_unattended_schedule_capability_readonly.rb',__dir__))
    assert_empty s.scan(/^require ['"][^'"]+['"]$/)
    assert_includes s,"'uci','-q','get'"
    assert_includes s,'Process.respond_to?(:fork)'
    assert_includes s,'Process.respond_to?(:setsid)'
    refute_match(/Process\.fork(?:\s|\()|Process\.setsid(?:\s|\()|Net::HTTP|curl|wget|system\(|\.write\(|File\.open\(|https?:\/\//,s)
    assert_includes s,'UPDATE_EXECUTION=NOT_VERIFIED'
  end
end
