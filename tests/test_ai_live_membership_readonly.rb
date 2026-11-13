# frozen_string_literal: true
require 'minitest/autorun'
require 'psych'
require 'tmpdir'
require_relative '../scripts/ai_live_membership_readonly'

class TestAiLiveMembershipReadOnly < Minitest::Test
  def sample
    [{'name'=>'TW1', 'server'=>'private.test', 'password'=>'NEVER_PRINT'},
     {'name'=>'HK1', 'server'=>'other.test', 'password'=>'NEVER_PRINT'}]
  end

  def runtime(names=%w[TW1 HK1], extra=nil)
    p = {'GLOBAL'=>{'type'=>'Selector'}, 'DIRECT'=>{'type'=>'Direct'}}
    names.each {|n| p[n]={'type'=>'Shadowsocks'} }
    p[extra]={'type'=>'Shadowsocks'} if extra
    {'proxies'=>p}
  end

  def test_exact_names_with_builtins_groups
    assert_equal 'EXACT_NAMES_ONLY', AiLiveMembership.check_names(sample,runtime)
  end

  def test_partial_or_extra_names_distinct
    assert_equal 'EXPECTED_MISSING', AiLiveMembership.check_names(sample,runtime(%w[TW1]))
    assert_equal 'UNEXPECTED_EXTRA_NAMES', AiLiveMembership.check_names(sample,runtime(%w[TW1 HK1], 'extra'))
  end

  def test_no_credentials_or_name_output
    assert_equal 'BAD_API_PAYLOAD', AiLiveMembership.check_names(sample,{'proxies'=>{'TW1'=>{'name'=>'TW1'}}})
    assert_equal 'BAD_DISK_NODES', AiLiveMembership.check_names([{'name'=>'DUP'}, {'name'=>'DUP'}],runtime)
    refute AiLiveMembership.check_names(sample,runtime).include?('TW1')
  end

  def test_unsafe_and_remote_controller_addresses_blocked
    assert_nil AiLiveMembership.local_controller('10.0.0.1:9090')
    assert_nil AiLiveMembership.local_controller('localhost:9090')
    assert_nil AiLiveMembership.local_controller('127.0.0.1:0')
    assert_nil AiLiveMembership.local_controller('0.0.0.0:70000')
    assert_equal 9090, AiLiveMembership.local_controller('127.0.0.1:9090')
    assert_equal 8888, AiLiveMembership.local_controller('0.0.0.0:8888')
    assert_equal 3000, AiLiveMembership.local_controller('127.0.0.1:3000')
  end

  def test_matching_disk_definitions_not_enough_for_full_reload
    Dir.mktmpdir do |dir|
      one = File.join(dir,'one.yaml')
      two = File.join(dir,'two.yaml')
      data = Psych.dump({'proxies'=>sample})
      File.write(one,data)
      File.write(two,data)
      assert_equal ['EXACT_NAMES_ONLY',2], AiLiveMembership.anonymous_catalog(one,two,runtime)
      File.write(two,Psych.dump({'proxies'=>[{'name'=>'TW1'}]}))
      assert_equal 'DISK_DIFFERENT', AiLiveMembership.anonymous_catalog(one,two,runtime)[0]
    end
  end

  def test_provider_mode_is_not_fake_covered_by_direct_list
    Dir.mktmpdir do |dir|
      a=File.join(dir,'a.yaml')
      b=File.join(dir,'b.yaml')
      content=Psych.dump({'proxies'=>sample,
                          'proxy-providers'=>{'Airport'=>{'type'=>'http'}}})
      File.write(a,content)
      File.write(b,content)
      assert_equal 'PROVIDERS_NOT_SUPPORTED_BY_THIS_PROBE',AiLiveMembership.anonymous_catalog(a,b,runtime)[0]
    end
  end

  def test_api_error_always_safe
    assert_nil AiLiveMembership.api_read("danger\nheader: injected",9090)
    assert_nil AiLiveMembership.api_read('a'*513,9090)
    assert_nil AiLiveMembership.api_read("bad\x00value",9090)
  end

  def test_no_router_environment_writes
    out, status = capture_io { AiLiveMembership.run }
    assert status == 0
    refute_match(/password|NEVER_PRINT|private.test/, out)
  end
end
