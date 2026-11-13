# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../scripts/ai_regional_pools'

class AiRegionalPoolsTest < Minitest::Test
  NOW=Time.iso8601('2026-11-13T12:00:00Z')
  def node(name,region,fp,rate: 0.99,rtt: 100,spd: 30,services: %w[chatgpt gemini notebooklm])
    time='2026-11-13T11:45:00Z'
    {'name'=>name,'fingerprint'=>fp,'egress'=>{'country'=>region,'verified'=>true,'fingerprint'=>fp,'tested_at'=>time},
     'health'=>{'success_rate'=>rate,'rtt_p95_ms'=>rtt,'throughput_mbps'=>spd,'samples'=>20,'fingerprint'=>fp,'tested_at'=>time},
     'services'=>services.to_h{|svc|[svc,{'status'=>'usable','fingerprint'=>fp,'tested_at'=>time}]}}
  end
  def test_all_source_entries_instead_of_parent_group
    records=[node('TW1','TW','a'),node('US1','US','b'),node('JP1','JP','c')]
    r=AiRegionalPools.build(records,coverage_verified:true,now:NOW)
    assert_equal 3,r['summary']['basic_qualified']
    assert_equal ['TW1'],r['all_services']['TW']
    assert_equal ['US1'],r['all_services']['US']
  end
  def test_country_uses_observed_egress_not_claimed_label
    n=node('Label-Taiwan','HK','id');n['claimed_country']='TW'
    r=AiRegionalPools.build([n],coverage_verified:true,now:NOW)
    assert_equal ['Label-Taiwan'],r['per_service']['chatgpt']['HK']
    refute r['per_service']['chatgpt'].key?('TW')
  end
  def test_speed_does_not_override_stability_when_ranking
    fast=node('FAST','TW','f',rate:0.97,rtt:20,spd:200)
    stable=node('STABLE','TW','s',rate:0.999,rtt:130,spd:20)
    r=AiRegionalPools.build([fast,stable],coverage_verified:true,now:NOW)
    assert_equal %w[STABLE FAST],r['all_services']['TW']
  end
  def test_service_qualification_separate
    a=node('HK-chatgpt','HK','a',services:['chatgpt'])
    r=AiRegionalPools.build([a],coverage_verified:true,now:NOW)
    assert_equal ['HK-chatgpt'],r['per_service']['chatgpt']['HK']
    refute r['per_service']['notebooklm'].key?('HK')
    assert_empty r['all_services']
  end
  def test_stale_service_or_changed_fingerprint_refused
    a=node('STALE','TW','a');a['services']['gemini']['tested_at']='2026-11-01T12:00:00Z'
    b=node('CHANGED','TW','b');b['health']['fingerprint']='old'
    r=AiRegionalPools.build([a,b],coverage_verified:true,now:NOW)
    assert_empty r['all_services']
    assert_equal ['STALE'],r['per_service']['chatgpt']['TW']
  end
  def test_duplicate_names_different_connections_excluded
    a=node('SAME','TW','a');b=node('SAME','TW','b')
    r=AiRegionalPools.build([a,b],coverage_verified:true,now:NOW)
    assert_equal 1,r['summary']['name_conflicts']
    assert_empty r['all_services']
  end
  def test_same_fingerprint_from_multiple_sources_is_deduped
    a=node('A','TW','same')
    r=AiRegionalPools.build([a,a.dup],coverage_verified:true,now:NOW)
    assert_equal 1,r['summary']['duplicate_fingerprints']
    assert_equal ['A'],r['all_services']['TW']
  end
  def test_unverified_country_and_bad_health_refused
    a=node('UNK','TW','a');a['egress']['verified']=false
    b=node('BAD','TW','b',rate:0.2)
    r=AiRegionalPools.build([a,b],coverage_verified:true,now:NOW)
    assert_empty r['per_service']['chatgpt']
  end
  def test_healthy_faster_backup_never_steals
    r=AiRegionalPools.decide(current:'A',ordered_candidates:%w[B A],mode:'AUTO',healthy:true,consecutive_node_failures:0,error_class:'node_network',now:NOW)
    assert_equal 'HOLD_HEALTHY',r['decision']
  end
  def test_manual_and_non_node_failures_never_switch
    base={current:'A',ordered_candidates:%w[A B],healthy:false,consecutive_node_failures:5,now:NOW}
    assert_equal 'HOLD_MANUAL',AiRegionalPools.decide(**base,mode:'MANUAL',error_class:'node_network')['decision']
    assert_equal 'HOLD_NON_NODE_FAILURE',AiRegionalPools.decide(**base,mode:'AUTO',error_class:'quota_429')['decision']
  end
  def test_suspect_cooldown_and_true_failure
    base={current:'A',ordered_candidates:%w[A B],mode:'AUTO',healthy:false,error_class:'node_network',now:NOW}
    assert_equal 'HOLD_SUSPECT',AiRegionalPools.decide(**base,consecutive_node_failures:1)['decision']
    assert_equal 'HOLD_COOLDOWN',AiRegionalPools.decide(**base,consecutive_node_failures:3,cooldown_until:'2026-11-13T12:20:00Z')['decision']
    assert_equal 'B',AiRegionalPools.decide(**base,consecutive_node_failures:3)['to']
  end
  def test_all_source_coverage_gate_prevents_premature_qualification
    assert_raises(ArgumentError){ AiRegionalPools.build([node('A','TW','a')],now:NOW) }
  end
  def test_malformed_cooldown_fails_closed
    r=AiRegionalPools.decide(current:'A',ordered_candidates:%w[A B],mode:'AUTO',healthy:false,consecutive_node_failures:4,error_class:'node_network',cooldown_until:'broken',now:NOW)
    assert_equal 'HOLD_INVALID_COOLDOWN',r['decision']
  end
  def test_no_verified_backup_does_not_cross_region
    r=AiRegionalPools.decide(current:'JP1',ordered_candidates:['JP1'],mode:'AUTO',healthy:false,consecutive_node_failures:4,error_class:'node_network',now:NOW)
    assert_equal 'NO_VERIFIED_BACKUP',r['decision']
  end
end
