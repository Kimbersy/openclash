require 'minitest/autorun'
require 'tmpdir'
require_relative '../scripts/ai_source_runtime_definitions_readonly'

class AiSourceRuntimeDefinitionsReadOnlyTests < Minitest::Test
  G=AiSourceRuntimeDefinitionsReadOnly
  def sample(n=58)
    {
      'proxies'=>Array.new(n) { |i|
        {'name'=>"TEST#{i}",'type'=>'vless','server'=>"private#{i}.invalid",
         'port'=>10000+i,'uuid'=>"sensitive-user-#{i}",
         'tls'=>true,'servername'=>"private-sni#{i}.invalid",
         'network'=>'ws','ws-opts'=>{'path'=>'/sensitive/private'},
         'skip-cert-verify'=>false}
      },
      'proxy-groups'=>[{'name'=>'AI','type'=>'select','proxies'=>['TEST0']}]
    }
  end
  def test_exact_full_definitions_even_if_order_differs
    a=sample
    b=Marshal.load(Marshal.dump(a))
    b['proxies'].reverse!
    m,status=G.compare(a,b)
    assert_equal 'SOURCE_RUNTIME_DISK_FULL_DEFINITIONS_MATCH',status
    assert_equal 58,m['SOURCE_EMBEDDED_LEAF_COUNT']
    assert_equal 58,m['RUNTIME_DISK_LEAF_COUNT']
    assert_equal 58,m['FULL_DEFINITION_MATCH_COUNT']
    assert_equal 0,m['SAME_NAME_DIFFERENT_DEFINITION_COUNT']
    assert_equal 0,m['SOURCE_ONLY_COUNT']
    assert_equal 0,m['RUNTIME_ONLY_COUNT']
    assert_equal 'YES',m['ORDER_ONLY_CHANGE']
    refute_includes m.inspect,'sensitive'
    refute_includes m.inspect,'private'
  end
  def test_same_name_different_password_tls_network_server_or_port_fails
    %w[uuid tls server port network].each do |key|
      a=sample
      b=Marshal.load(Marshal.dump(a))
      b['proxies'][0][key] = {'uuid'=>'new-secret','tls'=>false,
                             'server'=>'other.invalid','port'=>6553,
                             'network'=>'grpc'}[key]
      m,result=G.compare(a,b)
      assert_equal 'HOLD_SOURCE_RUNTIME_DEFINITION_DIFFERENCE',result
      assert_equal 57,m['FULL_DEFINITION_MATCH_COUNT']
      assert_equal 1,m['SAME_NAME_DIFFERENT_DEFINITION_COUNT']
      assert_equal 0,m['SOURCE_ONLY_COUNT']
    end
  end
  def test_nested_transport_changes_are_not_ignored
    a=sample
    b=Marshal.load(Marshal.dump(a))
    b['proxies'][17]['ws-opts']['path']='/changed-secret'
    metrics,mode=G.compare(a,b)
    assert_equal 'HOLD_SOURCE_RUNTIME_DEFINITION_DIFFERENCE',mode
    assert_equal 1,metrics['SAME_NAME_DIFFERENT_DEFINITION_COUNT']
  end
  def test_source_removed_runtime_extra_and_duplicate_name_hold
    a=sample
    b=Marshal.load(Marshal.dump(a))
    b['proxies'].delete_at(0)
    b['proxies'] << {'name'=>'OTHER','type'=>'ss'}
    m,st=G.compare(a,b)
    assert_equal 'HOLD_SOURCE_RUNTIME_DEFINITION_DIFFERENCE',st
    assert_equal 1,m['SOURCE_ONLY_COUNT']
    assert_equal 1,m['RUNTIME_ONLY_COUNT']
    b=sample
    b['proxies'][1]['name']=b['proxies'][0]['name']
    assert_equal 'HOLD_LAYOUT_OR_PROXY_PROVIDER',G.compare(a,b).last
  end
  def test_source_or_runtime_proxy_provider_mode_hold
    a=sample
    b=sample
    a['proxy-providers']={'remote'=>{'type'=>'http'}}
    assert_equal 'HOLD_LAYOUT_OR_PROXY_PROVIDER',G.compare(a,b).last
    a=sample
    b['proxy-providers']={'remote'=>{'type'=>'http'}}
    assert_equal 'HOLD_LAYOUT_OR_PROXY_PROVIDER',G.compare(a,b).last
  end
  def test_stable_read_does_not_need_download_or_log_secrets
    Dir.mktmpdir do |dir|
      file=File.join(dir,'test.yaml')
      File.write(file,"proxies:\n  - name: A\n    type: ss\n    password: secret\n")
      cfg=G.stable_read(file)
      assert_equal 'secret',cfg['proxies'][0]['password']
    end
  end
  def test_minimal_router_ruby_and_read_only_no_http
    code=File.binread(File.join(__dir__,'../scripts/ai_source_runtime_definitions_readonly.rb'))
    assert_equal ["require 'psych'"],code.scan(/^require ['"][^'"]+['"]$/)
    assert_includes code,"'uci','-q','get','openclash.config.config_path'"
    assert_includes code,'SOURCE_RUNTIME_DISK_FULL_DEFINITIONS_MATCH'
    assert_includes code,'MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED'
    assert_includes code,'ENABLED_SUBSCRIPTION_MERGE_PROVENANCE=NOT_VERIFIED'
    assert_includes code,'READ_ONLY_NO_HTTP=YES'
    refute_match(/https?:\/\/|Net::HTTP|curl|Process\.spawn|require_relative|system\(|\.write\(/,code)
    assert_includes code,'AUTO_SWITCH=OFF'
  end
end
