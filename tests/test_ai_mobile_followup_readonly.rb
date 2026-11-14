# frozen_string_literal: true
require 'minitest/autorun'
source=File.read(File.expand_path('../scripts/ai_mobile_followup_readonly.sh',__dir__))
body=source.split("<<'RUBY'\n",2).fetch(1).split("\nRUBY\n",2).fetch(0)
body=body.sub(/\nexit AiMobileFollowup\.run\s*\z/,"\n")
eval(body,TOPLEVEL_BINDING,'ai_mobile_followup_inline',1)
class TestAiMobileFollowup < Minitest::Test
  M=AiMobileFollowup
  def disk
    Array.new(58){|i|{'name'=>"disk_#{i}",'type'=>'Trojan','password'=>'private-synthetic-secret'}}
  end
  def api_data(expected)
    p=expected.to_h{|x|[x['name'],{'type'=>'Trojan'}]}
    p['AI selection']={'type'=>'Selector'}
    p['DIRECT']={'type'=>'Direct'}
    p['runtime-generated']={'type'=>'Direct'}
    p['new-private-node']={'type'=>'Trojan'}
    {'proxies'=>p}
  end
  def test_58_disk_names_all_present_plus_anonymous_extras
    e=disk
    result=M.count_summary(e,api_data(e))
    assert_equal({expected:58,present:58,extra:2,extra_direct:1,extra_other:1},result)
    refute_includes result.to_s,'private-synthetic-secret'
    refute_includes result.to_s,'new-private-node'
  end
  def test_missing_expected_name_is_not_silent_pass
    e=disk
    payload=api_data(e)
    payload['proxies'].delete(e.first['name'])
    assert_equal 57,M.count_summary(e,payload)[:present]
  end
  def test_reject_invalid_or_duplicate_disk_and_api
    e=disk
    e[1]['name']=e[0]['name']
    assert_nil M.count_summary(e,api_data(disk))
    assert_nil M.count_summary(disk,{'proxies'=>{'node'=>{'type'=>nil}}})
    assert_nil M.count_summary(disk,{'proxies'=>'bad'})
  end
  def test_bad_proc_clock_does_not_raise_or_print_details
    assert_equal 'CORE_TIME_UNAVAILABLE',M.core_clock_status('not-a-pid')
  end
  def test_minimal_requirements_do_not_invoke_time_or_download
    refute_includes source=(File.read(File.expand_path('../scripts/ai_mobile_followup_readonly.sh',__dir__))),"require 'time'"
    refute_match(/(?:wget|curl)[^\n]*github/i,source)
    assert_match(/--config','-'/,source)
    assert_match(/PRODUCTION_WRITES=NONE/,source)
  end
end
