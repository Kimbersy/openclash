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
  def tcp_row(address, port, ino, status='0A')
    "  0: #{address}:#{format('%04X',port)} 00000000:0000 #{status} 00000000:00000000 00:00000000 00000000 0 0 #{ino} 1 0000000000000000 100 0 0 10 0"
  end

  def test_ipv6_wildcard_owned_by_core_is_only_ipv4_mapped_candidate
    port=9911
    evidence=G.owner_class_from_rows(
      [],[['IPV6_WILDCARD','444']],{'444'=>true})
    assert_equal 'IPV6_WILDCARD_IPV4_CANDIDATE',evidence.first
    assert_equal ['444'],evidence.last
    assert_nil G.owner_class_from_rows([], [['IPV6_OTHER','444']],{'444'=>true})
    assert_nil G.owner_class_from_rows([], [['IPV6_WILDCARD','444']],{})
    assert_nil G.owner_class_from_rows([], [], {})
  end

  def test_no_unowned_ipv4_socket_may_receive_secret
    assert_nil G.owner_class_from_rows(
      [['IPV4_LOOPBACK','800']], [['IPV6_WILDCARD','900']], {'900'=>true})
    assert_nil G.owner_class_from_rows([['IPV4_OTHER','800']],[], {'800'=>true})
    p=G.owner_class_from_rows([['IPV4_LOOPBACK','800']],[], {'800'=>true})
    assert_equal 'IPV4_CORE_SOCKET',p.first
  end

  def test_strict_ipv4_request_only_and_no_ipv6_fallback
    script=File.read(File.join(__dir__,'../scripts/ai_live_rule_provider_readonly.rb'))
    assert_includes script,"'--ipv4','--noproxy','*'"
    assert_includes script,'http://127.0.0.1:'
    refute_match(/http:\/\/\[::1\]|--ipv6|https:\/\/\[::1\]/,script)
    assert_includes script,'HOLD_IPV4_LOCAL_API_UNAVAILABLE'
    assert_includes script,'IPV6_WILDCARD_IPV4_CANDIDATE'
    assert_includes script,'HOLD_CONTROLLER_OWNER_CHANGED'
  end

  def test_real_proc_socket_formats_are_identified_anonymously
    require 'tempfile'
    file=Tempfile.new('synth-proc')
    begin
      file.write("  sl  local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode\n")
      file.write(tcp_row('00000000000000000000000000000000',9090,'445')+"\n")
      file.write(tcp_row('00000000000000000000000001000000',9090,'446')+"\n")
      file.flush
      result=G.socket_rows(file.path,9090,v6:true)
      assert_equal [['IPV6_WILDCARD','445'],['IPV6_OTHER','446']],result
    ensure
      file.close!
    end
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
