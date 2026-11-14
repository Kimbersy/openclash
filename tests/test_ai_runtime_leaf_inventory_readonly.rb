require 'minitest/autorun'
require_relative '../scripts/ai_runtime_leaf_inventory_readonly'

class AiRuntimeLeafInventoryReadOnlyTests < Minitest::Test
  G=AiRuntimeLeafNamesReadOnly
  def cfg(n=58)
    {
      'proxies'=>Array.new(n){|i| {'name'=>"node#{i}",'type'=>'ss',
          'server'=>'SECRET_SERVER_NEVER_PRINT','password'=>'SECRET_PASS_NEVER_PRINT'}},
      'proxy-groups'=>[{'name'=>'🤖 AI','type'=>'select','proxies'=>['node0']},
                        {'name'=>'FamilyOther','type'=>'select','proxies'=>['DIRECT']}],
      'rule-providers'=>Array.new(20).each_with_index.to_h{|_,i| ["rule#{i}", {'type'=>'http'}]}
    }
  end
  def api(n=58)
    h = {'GLOBAL'=>{'type'=>'Selector'},'DIRECT'=>{'type'=>'Direct'},
      'REJECT'=>{'type'=>'Reject'}, '🤖 AI'=>{'type'=>'Selector'},
      'FamilyOther'=>{'type'=>'Selector'}}
    n.times{|i|h["node#{i}"]={'type'=>'Shadowsocks','server'=>'SENSITIVE_NEVER_PRINT'}}
    {'proxies'=>h}
  end
  def snapshot(n=58)
    s,status=G.expected_leaf_snapshot(cfg(n))
    assert_equal 'SNAPSHOT_READY',status
    s
  end
  def test_live_58_leaves_match_not_20_rule_providers_or_parent_group_size
    counters,status=G.compare_snapshot(snapshot,api)
    assert_equal 'LIVE_LEAF_NAME_COVERAGE_PASS',status
    assert_equal 58,counters['CONFIG_EMBEDDED_LEAF_COUNT']
    assert_equal 58,counters['API_EXPECTED_LEAF_PRESENT']
    assert_equal 0,counters['API_EXPECTED_LEAF_MISSING']
    assert_equal 0,counters['API_EXTRA_UNTRUSTED_LEAF']
    refute_includes counters.inspect,'SECRET_SERVER_NEVER_PRINT'
    refute_includes counters.inspect,'SENSITIVE_NEVER_PRINT'
  end
  def test_new_subscription_node_count_not_hardcoded_58
    counters,status=G.compare_snapshot(snapshot(74),api(74))
    assert_equal 'LIVE_LEAF_NAME_COVERAGE_PASS',status
    assert_equal 74,counters['CONFIG_EMBEDDED_LEAF_COUNT']
  end
  def test_missing_extra_and_unknown_group_are_held
    s=snapshot
    m=api
    m['proxies'].delete('node0')
    counters,status=G.compare_snapshot(s,m)
    assert_equal 'HOLD_RUNTIME_LEAF_MISMATCH',status
    assert_equal 1,counters['API_EXPECTED_LEAF_MISSING']
    m=api
    m['proxies']['untrusted-extra']={'type'=>'Trojan'}
    counters,status=G.compare_snapshot(s,m)
    assert_equal 'HOLD_RUNTIME_LEAF_MISMATCH',status
    assert_equal 1,counters['API_EXTRA_UNTRUSTED_LEAF']
    m=api
    m['proxies']['new-unknown-group']={'type'=>'Selector'}
    counters,status=G.compare_snapshot(s,m)
    assert_equal 'HOLD_RUNTIME_LEAF_MISMATCH',status
    assert_equal 1,counters['API_UNACCOUNTED_GROUP']
  end
  def test_name_collision_and_proxy_provider_mode_hold_closed
    source=cfg
    source['proxies'][1]['name']='node0'
    assert_equal 'HOLD_NAME_COLLISION',G.expected_leaf_snapshot(source).last
    source=cfg
    source['proxy-providers']={'other'=>{'type'=>'http'}}
    assert_equal 'HOLD_PROXY_PROVIDER_MODE',G.expected_leaf_snapshot(source).last
    source=cfg
    source['proxies'][0]['name']='🤖 AI'
    assert_equal 'HOLD_NAME_COLLISION',G.expected_leaf_snapshot(source).last
  end
  def test_untrusted_api_shape_or_expected_group_are_hold
    s=snapshot
    assert_equal 'HOLD_API_LAYOUT',G.compare_snapshot(s,{'proxies'=>[]}).last
    a=api
    a['proxies']['node0']={'type'=>'Selector'}
    counters,status=G.compare_snapshot(s,a)
    assert_equal 'HOLD_RUNTIME_LEAF_MISMATCH',status
    assert_equal 1,counters['API_EXPECTED_AS_GROUP']
    assert_equal 1,counters['API_EXPECTED_LEAF_MISSING']
  end
  def test_controller_is_same_verified_ipv4_only_path_and_no_secrets_printed
    source=File.binread(File.join(__dir__,'../scripts/ai_runtime_leaf_inventory_readonly.rb'))
    assert_equal ["require 'psych'"],source.scan(/^require ['"][^'"]+['"]$/)
    assert_includes source,"'--ipv4','--noproxy','*'"
    assert_includes source,'http://127.0.0.1:#{port}/proxies'
    refute_match(/http:\/\/\[::1\]|--ipv6|Process\.spawn|require_relative|Net::HTTP/,source)
    assert_includes source,'LIVE_FULL_CONNECTION_FINGERPRINTS=NOT_VERIFIED'
    assert_includes source,'ENABLED_SUBSCRIPTION_SOURCE_COVERAGE=NOT_VERIFIED'
    assert_includes source,'PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN'
    assert_includes source,'AUTO_SWITCH=OFF'
    refute_includes source,'/proxies/node0'
  end
end
