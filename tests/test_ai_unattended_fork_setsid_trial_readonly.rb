# frozen_string_literal: true
require 'minitest/autorun'
require 'stringio'
require_relative '../scripts/ai_unattended_fork_setsid_trial_readonly'

class AiUnattendedForkSetsidTrialReadOnlyTests < Minitest::Test
  G=AiUnattendedForkSetsidTrialReadOnly

  def test_bounded_one_shot_child_is_reaped_on_ci_host
    cmd=File.expand_path('../scripts/ai_unattended_fork_setsid_trial_readonly.rb',__dir__)
    out=IO.popen(['ruby',cmd],err:File::NULL,&:read)
    assert_includes out,'FORK_SESSION_TRIAL=START ONE_SHOT=YES NO_HTTP=YES'
    assert_match(/FORK_SESSION_TRIAL_RESULT=(CHILD_SESSION_ISOLATION_PASS|HOLD_[A-Z_]+)/,out)
    if out.include?('CHILD_SESSION_ISOLATION_PASS')
      assert_includes out,'DIRECT_CHILD_REAPED=YES'
    end
    assert_includes out,'BACKGROUND_SERVICE=NOT_INSTALLED CRON_PROCD=UNCHANGED'
    assert_includes out,'SUBSCRIPTION_AND_CORE=NOT_READ UPDATE_TRIGGERED=NO'
    assert_includes out,'ALLOW_RECONCILE=NO ALLOW_SWITCH=NO'
    assert_includes out,'PRODUCTION_CONFIG=UNCHANGED'
    refute_match(/SECRET_|https?:\/\/|password|token=|\/etc\/openclash\//i,out)
  end

  def test_missing_fork_method_stays_hold_without_fork
    out=StringIO.new
    previous=$stdout
    begin
      $stdout=out
      G.stub(:run,proc {puts 'FORK_SESSION_TRIAL_RESULT=HOLD_METHOD_UNAVAILABLE'}) do
        G.run
      end
    ensure
      $stdout=previous
    end
    assert_includes out.string,'HOLD_METHOD_UNAVAILABLE'
  end

  def test_target_requires_zero_external_libraries_and_no_external_effects
    source=File.binread(File.expand_path('../scripts/ai_unattended_fork_setsid_trial_readonly.rb',__dir__))
    assert_empty source.scan(/^require ['"][^'"]+['"]$/)
    for guard in ['MAX_SECONDS = 4','Process::CLOCK_MONOTONIC',
       'Process.waitpid2','Process::WNOHANG','Process.setsid',
       'DIRECT_CHILD_REAPED=','CHILD_SESSION_ISOLATION_PASS',
       'BACKGROUND_SERVICE=NOT_INSTALLED','AUTO_SWITCH=OFF']
      assert_includes source,guard
    end
    refute_match(/Process\.spawn|Net::HTTP|curl|wget|https?:\/\/|system\(|File\.(?:open|write|binwrite)|require_relative|OpenClash.*reload|crontab -/,source)
    assert_includes source,"Process.kill('TERM',child_pid)"
    assert_includes source,'Process.waitpid2(child_pid)'
  end
end
