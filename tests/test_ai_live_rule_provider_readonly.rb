require 'minitest/autorun'
require 'tmpdir'
require_relative '../scripts/ai_live_rule_provider_readonly'

class AiLiveRuleProviderReadOnlyTests < Minitest::Test
  G=AiLiveRuleProviderReadOnly
  def expected
    Hash.new.tap do |h|
      19.times { |i| h["SYNTHETIC_#{i}"] = {'type'=>'http','format'=>'yaml'} }
      h['PRIVATE_MRS_NAME'] = {'type'=>'http','format'=>'mrs'}
    end
  end
  def api(positives: 18, zeros: 1, unknown: 1, extra: 0)
    list=expected.keys
    result={}
    list.each_with_index do |n,i|
      rc=i < positives ? 20 : i < positives+zeros ? 0 : 'unknown'
      result[n]={'type'=>'Rule','vehicleType'=>'HTTP','ruleCount'=>rc}
    end
    extra.times { |i| result["built_in_#{i}"]={'type'=>'Rule','ruleCount'=>0} }
    {'providers'=>result}
  end
  def test_all_20_present_and_mrs_count_uncertain_not_faked
    status,c=G.classify(expected,api)
    assert_equal 'API_RULE_PROVIDER_CATALOG_READ',status
    assert_equal 20,c['API_PROVIDER_COUNT']
    assert_equal 20,c['API_EXPECTED_PRESENT']
    assert_equal 0,c['API_EXPECTED_MISSING']
    assert_equal 18,c['API_RULECOUNT_POSITIVE']
    assert_equal 1,c['API_RULECOUNT_ZERO']
    assert_equal 1,c['API_RULECOUNT_UNKNOWN']
    assert_equal 'UNKNOWN',c['MRS_RUNTIME_RULECOUNT']
    refute_includes c.inspect,'PRIVATE_MRS_NAME'
  end
  def test_mrs_positive_can_be_reported_without_implying_file_format
    status,c=G.classify(expected,api(positives:20,zeros:0,unknown:0))
    assert_equal 'API_RULE_PROVIDER_CATALOG_READ',status
    assert_equal 'POSITIVE',c['MRS_RUNTIME_RULECOUNT']
    assert_equal 20,c['API_RULECOUNT_POSITIVE']
  end
  def test_missing_provider_and_untrusted_extra
    a=api(extra:2)
    a['providers'].delete('SYNTHETIC_1')
    status,c=G.classify(expected,a)
    assert_equal 'HOLD_RUNTIME_PROVIDER_MISSING',status
    assert_equal 19,c['API_EXPECTED_PRESENT']
    assert_equal 1,c['API_EXPECTED_MISSING']
    assert_equal 2,c['API_EXTRA_UNTRUSTED']
  end
  def test_refuse_bad_api_shape_and_mrs_shape
    assert_equal 'HOLD_API_LAYOUT',G.classify(expected,{'providers'=>[]}).first
    assert_equal 'HOLD_API_LAYOUT',G.classify(expected,{'providers'=>{'secret'=>nil}}).first
    cfg=expected
    cfg['PRIVATE_MRS_NAME']['format']='yaml'
    assert_equal 'HOLD_EXPECTED_MRS_COUNT',G.classify(cfg,api).first
  end
  def test_controller_rejects_remote_and_strange_host
    [nil,'192.0.2.5:9090','localhost:9090','[::]:9090','127.0.0.1:0','0.0.0.0:90000'].each do |addr|
      assert_nil G.controller_port(addr)
    end
    assert_equal 9090,G.controller_port('127.0.0.1:9090')
    assert_equal 9090,G.controller_port('0.0.0.0:9090')
  end
  def test_unsafe_secret_fails_before_any_curl_command
    assert_nil G.api_read("TOKEN\r\nheader: x",9090)
    assert_nil G.api_read('X'*513,9090)
    assert_nil G.api_read("abc\x00def",9090)
  end
  def test_runtime_depends_only_on_verified_psych_and_read_only_http
    script=File.read(File.join(__dir__,'../scripts/ai_live_rule_provider_readonly.rb'))
    assert_equal ["require 'psych'"],script.scan(/^require ['"][^'"]+['"]$/)
    assert_includes script,'/providers/rules'
    assert_includes script,"'--request','GET'"
    refute_match(/Process\.spawn|require_relative|Net::HTTP|Timeout\./,script)
    assert_includes script,'PROVIDER_REFRESH=NOT_RUN'
    assert_includes script,'LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
    assert_includes script,"'--noproxy','*'"
  end
  def test_no_core_means_anonymous_hold
    out,_=capture_io { G.run }
    assert_match(/LIVE_RULE_RESULT=HOLD_CORE_NOT_UNIQUE/,out)
    refute_match(/PRIVATE_MRS_NAME|TOKEN|SYNTHETIC_/,out)
  end
end
