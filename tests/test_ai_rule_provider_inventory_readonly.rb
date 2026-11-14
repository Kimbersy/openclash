# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'psych'
require_relative '../scripts/ai_rule_provider_inventory_readonly'

class TestAiRuleProviderInventory < Minitest::Test
  M=AiRuleProviderInventory
  def configuration
    {
      'rule-providers'=>{
        'REMOTE_PRIVATE_DO_NOT_PRINT'=>{'type'=>'http','url'=>'https://token:PRIVATE-SECRET@example.invalid/rules.mrs',
          'path'=>'./cache/valid.mrs','behavior'=>'domain','format'=>'mrs'},
        'LOCAL_PRIVATE_DO_NOT_PRINT'=>{'type'=>'file','path'=>'./cache/missing.yaml',
          'behavior'=>'classical'},
        'INLINE_PRIVATE_DO_NOT_PRINT'=>{'type'=>'inline','payload'=>['DOMAIN-SUFFIX,secret.example.invalid']}
      },
      'rules'=>['RULE-SET,REMOTE_PRIVATE_DO_NOT_PRINT,🤖 AI','MATCH,DIRECT'],
      'proxy-groups'=>[{'name'=>'🤖 AI','type'=>'select','use'=>['test']}],
      'proxy-providers'=>{'confidential'=>{'type'=>'http'}}
    }
  end
  def with_home
    Dir.mktmpdir('test-rule-provider-home-') do |base|
      File.chmod(0700,base)
      Dir.mkdir("#{base}/cache",0700)
      File.write("#{base}/cache/valid.mrs",'DUMMY-CACHE-CONTENT')
      yield base
    end
  end
  def test_types_and_cache_are_anonymous_and_no_file_contents_exposed
    with_home do |home|
      cfg=configuration
      result,status=M.classify(cfg,home)
      assert_equal 'RULE_PROVIDER_SHAPE_CLASSIFIED',status
      assert_equal 1,result['type_http']
      assert_equal 1,result['type_file']
      assert_equal 1,result['type_inline']
      assert_equal 1,result['cache_local_regular']
      assert_equal 1,result['cache_missing']
      assert_equal 1,result['inline_payload_present']
      assert_equal 1,result['ruleset_reference_present']
      assert_equal 1,result['proxy_providers_present']
      assert_equal 1,result['group_provider_use_present']
      str=result.inspect+status
      %w[PRIVATE-SECRET example.invalid REMOTE_PRIVATE_DO_NOT_PRINT DUMMY-CACHE-CONTENT].each do |term|
        refute_includes str,term
      end
      assert File.exist?("#{home}/cache/valid.mrs"),'no cache modification'
    end
  end
  def test_missing_http_path_is_not_made_up_from_secret_url
    with_home do |home|
      cfg=configuration
      cfg['rule-providers']['REMOTE_PRIVATE_DO_NOT_PRINT'].delete('path')
      result,status=M.classify(cfg,home)
      assert_equal 'RULE_PROVIDER_SHAPE_CLASSIFIED',status
      assert_equal 1,result['cache_no_explicit_path']
      assert_equal 0,result.fetch('cache_local_regular',0)
    end
  end
  def test_outside_cache_symlink_and_missing_are_not_accepted
    with_home do |home|
      assert_equal 'outside_home',M.cache_status('/etc/passwd',home)
      assert_equal 'outside_home',M.cache_status('../outside.yaml',home)
      assert_equal 'missing',M.cache_status('cache/absent.mrs',home)
      File.symlink('/etc/passwd',"#{home}/cache/link")
      assert_equal 'unsafe_path',M.cache_status('./cache/link',home)
      File.symlink('/etc',"#{home}/cache/outside_parent")
      assert_equal 'outside_home',M.cache_status('./cache/outside_parent/passwd',home)
      assert_equal 'no_explicit_path',M.cache_status(nil,home)
      assert_equal 'unsafe_path',M.cache_status("cache/\0bad",home)
    end
  end
  def test_geo_rule_and_bundle_dependencies_classified_one_pass
    with_home do |home|
      cfg=configuration
      cfg['rule-providers']['REMOTE_PRIVATE_DO_NOT_PRINT']['path-in-bundle']='geo/geosite/private.mrs'
      cfg['rules']=['AND,((GEOSITE,google),(RULE-SET,private)),🤖 AI','GEOIP,CN,DIRECT']
      cfg['geodata-mode']=true
      d,v=M.classify(cfg,home)
      assert_equal 'RULE_PROVIDER_SHAPE_CLASSIFIED',v
      assert_equal 1,d['bundle_dependency']
      assert_equal 1,d['geo_reference_present']
      assert_equal 1,d['geo_mode_enabled']
      assert_equal 1,d['ruleset_reference_present']
    end
  end
  def test_layout_fail_closed_and_no_requires_beyond_proven_psych
    with_home do |home|
      [{}, {'rule-providers'=>[]}, {'rule-providers'=>{}},
       {'rule-providers'=>{'bad'=>nil}}].each do |cfg|
        _,decision=M.classify(cfg,home)
        assert_match(/^HOLD_/,decision)
      end
      file=File.expand_path('../scripts/ai_rule_provider_inventory_readonly.rb',__dir__)
      source=File.read(file)
      assert_equal ["require 'psych'"],source.lines.grep(/^require /).map(&:strip)
      assert_includes source,'PRIVATE_COPY_TEST=NOT_RUN'
      assert_includes source,'RULE_CONTENT=NOT_READ'
      refute_includes source,'File.write('
      refute_includes source,'Process.spawn('
      refute_includes source,'Net::HTTP'
      refute_includes source,'curl '
    end
  end
end
