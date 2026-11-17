require 'minitest/autorun'
require_relative '../scripts/ai_refresh_observer_runtime_preflight_readonly'

class AiRefreshObserverRuntimePreflightTests < Minitest::Test
  G=AiRefreshObserverRuntimePreflight
  def test_host_primitives_gate_and_no_false_commit_success
    states=G.assess
    assert_equal %w[RUBY_FILE_NOFOLLOW RUBY_PRIVATE_FLOCK RUBY_MONOTONIC_CLOCK RUBY_SIGNAL_TRAP].sort,
      states.keys.sort
    states.values.each { |value| assert_includes %w[PASS HOLD],value }
    assert_equal 'PASS',states['RUBY_FILE_NOFOLLOW'] if File.const_defined?(:NOFOLLOW)
  end

  def test_one_shot_output_is_aggregate_and_discloses_no_private_data
    cmd=File.expand_path('../scripts/ai_refresh_observer_runtime_preflight_readonly.rb',__dir__)
    output=IO.popen(['ruby',cmd],err:File::NULL,&:read)
    assert_includes output,'PASSIVE_RUNTIME_PREFLIGHT=START ONE_SHOT_NO_HTTP=YES'
    assert_match(/PASSIVE_RUNTIME_PREFLIGHT_RESULT=(PRIMITIVES_AVAILABLE_ONLY|HOLD_RUNTIME_CAPABILITY)/,output)
    assert_includes output,'UPDATER_CONTENT=NOT_READ REFRESH_COMMIT=NOT_VERIFIED'
    assert_includes output,'LISTENER_INSTALLED=NO PASSIVE_OBSERVER_INSTALLED=NO'
    assert_includes output,'AUTO_SWITCH=OFF'
    refute_match(/https:\/\/|PRIVATE_SECRET|\/etc\/openclash\/config\//,output)
  end

  def test_minimal_router_ruby_and_zero_invasive_device_scope
    s=File.binread(File.expand_path('../scripts/ai_refresh_observer_runtime_preflight_readonly.rb',__dir__))
    assert_equal [],s.scan(/^require ['"][^'"]+['"]$/)
    assert_includes s,'File::NOFOLLOW'
    assert_includes s,'File::LOCK_EX|File::LOCK_NB'
    assert_includes s,'Process::CLOCK_MONOTONIC'
    assert_includes s,"trap('TERM')"
    assert_includes s,'PRODUCTION_CONFIG=UNCHANGED'
    refute_match(/Net::HTTP|curl|wget|Process\.spawn|system\(|require_relative|\.write\(|https?:\/\//,s)
  end
end
