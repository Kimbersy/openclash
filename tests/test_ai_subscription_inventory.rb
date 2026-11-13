# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../scripts/ai_subscription_inventory'

class AiSubscriptionInventoryTest < Minitest::Test
  def test_embedded_node_pool_is_not_parent_ai_group_member_count
    cfg={'proxies'=>Array.new(58){|i|{'name'=>"private#{i}", 'password'=>'secret'}},
         'proxy-groups'=>[{'name'=>'🤖 AI','type'=>'select','proxies'=>Array.new(13){|i|"group#{i}"}}]}
    result=AiSubscriptionInventory.classify(cfg)
    assert_equal 58,result[:embedded]
    assert_equal 58,result[:unique_names]
    assert_equal 'UNVERIFIED_NEEDS_MERGE_PROVENANCE',result[:source_coverage]
    refute_includes result.inspect,'secret'
  end
  def test_providers_added_beyond_embedded_and_conflicts_not_hidden
    cfg={'proxies'=>[{'name'=>'A'},{'name'=>'B'}],'proxy-providers'=>{'s1'=>{},'s2'=>{}}}
    loaded={'providers'=>{'s1'=>{'proxies'=>[{'name'=>'C'},{'name'=>'D'}]},'s2'=>{'proxies'=>[{'name'=>'B'},{'name'=>'E'}]}}}
    r=AiSubscriptionInventory.classify(cfg,loaded)
    assert_equal 2,r[:embedded]
    assert_equal 2,r[:provider_definitions]
    assert_equal 4,r[:provider_nodes_loaded]
    assert_equal 5,r[:unique_names]
    assert_equal 1,r[:name_conflicts]
    assert_equal 'READABLE',r[:provider_status]
  end
  def test_provider_missing_is_partial_not_a_verified_full_pool
    cfg={'proxy-providers'=>{'s1'=>{},'s2'=>{}},'proxies'=>[]}
    r=AiSubscriptionInventory.classify(cfg,{'providers'=>{'s1'=>{'proxies'=>[{'name'=>'A'}]}}})
    assert_equal 'PARTIAL',r[:provider_status]
    assert_equal 1,r[:provider_nodes_loaded]
  end
  def test_wrong_api_envelope_is_not_falsely_claimed_as_loaded
    cfg={'proxy-providers'=>{'s1'=>{}}}
    r=AiSubscriptionInventory.classify(cfg,{'s1'=>{'proxies'=>[{'name'=>'A'}]}})
    assert_equal 'UNVERIFIED',r[:provider_status]
    assert_equal 0,r[:provider_nodes_loaded]
  end
  def test_empty_provider_envelope_is_partial_not_complete
    r=AiSubscriptionInventory.classify({'proxy-providers'=>{'s1'=>{}}},{'providers'=>{}})
    assert_equal 'PARTIAL',r[:provider_status]
  end
  def test_unavailable_provider_is_unverified
    r=AiSubscriptionInventory.classify({'proxy-providers'=>{'s1'=>{}}})
    assert_equal 'UNVERIFIED',r[:provider_status]
    assert_equal 0,r[:provider_nodes_loaded]
  end
  def test_uci_unnamed_sections_counts_only_explicit_enabled_flags
    uci="openclash.@config_subscribe[0]=config_subscribe\nopenclash.@config_subscribe[0].enabled='1'\n" \
        "openclash.@config_subscribe[1]=config_subscribe\nopenclash.@config_subscribe[1].enabled='0'\n" \
        "openclash.@config_subscribe[2]=config_subscribe\nopenclash.@config_subscribe[2].url='private'\n"
    r=AiSubscriptionInventory.classify({},nil,uci)
    assert_equal 3,r[:subscribe_sections]
    assert_equal 1,r[:subscribe_flag_enabled]
    assert_equal 1,r[:subscribe_flag_unknown]
    refute_includes r.inspect,'private'
  end
  def test_no_input_does_not_claim_all_sources
    assert_raises(RuntimeError){ AiSubscriptionInventory.classify('invalid') }
  end
end
