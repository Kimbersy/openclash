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
  def test_official_pass_rule_preset_extra_is_classified_by_name_and_type
    s = snapshot
    response = api
    response['proxies']['PASS-RULE'] = {'type'=>'PassRule'}
    counts, status = G.compare_snapshot(s,response)
    assert_equal 'LIVE_LEAF_NAME_COVERAGE_PASS',status
    assert_equal 58,counts['API_EXPECTED_LEAF_PRESENT']
    assert_equal 0,counts['API_EXPECTED_LEAF_MISSING']
    assert_equal 0,counts['API_EXTRA_UNTRUSTED_LEAF']
    assert_equal 1,counts['API_EXTRA_PRESET_MATCHED']
    assert_equal 0,counts['API_EXTRA_PRESET_TYPE_MISMATCH']
    refute_includes counts.inspect,'PASS-RULE'
  end

  def test_preset_name_with_real_proxy_type_is_not_silently_whitelisted
    s = snapshot
    response = api
    response['proxies']['PASS-RULE'] = {'type'=>'Trojan','server'=>'SENSITIVE'}
    counts, status = G.compare_snapshot(s,response)
    assert_equal 'HOLD_RUNTIME_LEAF_MISMATCH',status
    assert_equal 1,counts['API_EXTRA_PRESET_TYPE_MISMATCH']
    assert_equal 1,counts['API_EXTRA_UNTRUSTED_LEAF']
    refute_includes counts.inspect,'SENSITIVE'
  end

  def test_special_unknown_type_or_unlisted_name_stays_on_hold
    s = snapshot
    response = api
    response['proxies']['SECRET_EXTRA'] = {'type'=>'PassRule'}
    counts, status = G.compare_snapshot(s,response)
    assert_equal 'HOLD_RUNTIME_LEAF_MISMATCH',status
    assert_equal 1,counts['API_EXTRA_SPECIAL_TYPE_UNCLASSIFIED']
    assert_equal 1,counts['API_EXTRA_UNTRUSTED_LEAF']
    refute_includes counts.inspect,'SECRET_EXTRA'
    response = api
    response['proxies']['SECRET_EXTRA'] = {'type'=>'Trojan'}
    counts, status = G.compare_snapshot(s,response)
    assert_equal 'HOLD_RUNTIME_LEAF_MISMATCH',status
    assert_equal 1,counts['API_EXTRA_OTHER_UNCLASSIFIED']
    assert_equal 1,counts['API_EXTRA_UNTRUSTED_LEAF']
  end

  def test_reserved_preset_names_cannot_collide_with_user_groups_or_leaves
    source = cfg
    source['proxy-groups'][0]['name']='PASS-RULE'
    assert_equal 'HOLD_NAME_COLLISION',G.expected_leaf_snapshot(source).last
    source = cfg
    source['proxies'][0]['name']='PASS-RULE'
    assert_equal 'HOLD_NAME_COLLISION',G.expected_leaf_snapshot(source).last
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
  def test_transient_unrelated_fd_close_does_not_fake_owner_changed
    fd_paths=%w[/proc/fake/10 /proc/fake/11 /proc/fake/12 /proc/fake/13]
    reader=lambda do |fd|
      case fd
      when '/proc/fake/10' then 'socket:[123456]'
      when '/proc/fake/11' then raise Errno::ENOENT
      when '/proc/fake/12' then raise Errno::EBADF
      else 'socket:[9999]'
      end
    end
    sockets=G.match_listener_fds(fd_paths,['123456'],reader)
    assert_equal({'123456'=>true},sockets)
    assert_equal 'IPV6_WILDCARD_IPV4_CANDIDATE',
      G.owner_class_from_rows([], [['IPV6_WILDCARD','123456']],sockets).first
  end

  def test_closed_listener_fd_never_counts_as_owned
    reader=lambda { |_path| raise Errno::ENOENT }
    sockets=G.match_listener_fds(['/proc/fake/10'], ['123456'], reader)
    assert_equal({},sockets)
    assert_nil G.owner_class_from_rows([], [['IPV6_WILDCARD','123456']],sockets)
  end

  def test_socket_inode_replacement_requires_fail_closed_recheck
    old_owner=G.owner_class_from_rows([], [['IPV6_WILDCARD','123456']],{'123456'=>true})
    new_owner=G.owner_class_from_rows([], [['IPV6_WILDCARD','654321']],{'654321'=>true})
    refute_equal old_owner,new_owner
    assert_nil G.owner_class_from_rows([], [['IPV6_OTHER','123456']],{'123456'=>true})
    assert_nil G.owner_class_from_rows([], [['IPV6_WILDCARD','654321']],{'123456'=>true})
  end

  def test_unexpected_fd_errors_are_not_ignored_and_budgets_fail_closed
    reader=lambda { |_path| raise Errno::EACCES }
    assert_nil G.match_listener_fds(['/proc/fake/10'],['123456'],reader)
    assert_nil G.match_listener_fds([],['123456'],reader)
    assert_nil G.match_listener_fds(['/proc/fake/10'],[],reader)
    assert_nil G.match_listener_fds(['/proc/fake/10'],['invalid'],reader)
  end

  def test_linux_proc_starttime_parse_handles_spaces_and_missing_field
    prefix=Array.new(18,'1').join(' ')
    stat="123 (mihomo process (testing)) S #{prefix} 432109 99"
    # S is field 3; eighteen dummy fields 4..21, then field 22 starttime.
    assert_equal '432109',G.proc_starttime(stat)
    assert_match(/\A[0-9]+\z/,G.proc_starttime(File.binread('/proc/self/stat')))
    assert_nil G.proc_starttime('not a proc stat')
    assert_nil G.proc_starttime('55 (mihomo) S 1 2')
    assert_nil G.proc_starttime('')
  end

  def test_post_get_checks_separate_process_change_vs_fd_unavailable
    script=File.binread(File.join(__dir__,'../scripts/ai_runtime_leaf_inventory_readonly.rb'))
    assert_includes script,'HOLD_CORE_PROCESS_CHANGED'
    assert_includes script,'HOLD_CONTROLLER_OWNER_RECHECK_UNAVAILABLE'
    assert_includes script,'HOLD_CONTROLLER_OWNER_CHANGED'
    assert_includes script,'identity_before == core_process_identity(pid)'
    assert_includes script,'evidence == evidence_after'
    assert_includes script,'File.readlink("/proc/#{pid}/exe")'
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
    assert_includes source,"'PASS-RULE' => 'PassRule'"
    assert_includes source,'API_EXTRA_PRESET_TYPE_MISMATCH'
    refute_includes source,'/proxies/node0'
  end
end
