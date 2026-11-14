# frozen_string_literal: true
require 'minitest/autorun'
require 'psych'
require_relative '../scripts/ai_real_config_private_copy_native_gate'

class TestAiRealPrivateCopy < Minitest::Test
  M = AiNotebookPrivateCopy
  def source
    { 'mode'=>'rule', 'allow-lan'=>false, 'mixed-port'=>7890,
      'dns'=>{'enable'=>false},
      'secret'=>'SYNTHETIC_DO_NOT_PRINT_SECRET',
      'proxies'=>[
        {'name'=>'TEST_0','type'=>'http','server'=>'192.0.2.1','port'=>8080,
         'password'=>'SYNTHETIC_DO_NOT_PRINT_PASSWORD'},
        {'name'=>'TEST_1','type'=>'http','server'=>'192.0.2.2','port'=>8080}
      ],
      'proxy-groups'=>[
        {'name'=>'🤖 AI','type'=>'select','proxies'=>['TEST_0','DIRECT']},
        {'name'=>'🏰 Disney+','type'=>'select','proxies'=>['DIRECT']}
      ],
      'rules'=>['DOMAIN-SUFFIX,chatgpt.com,🤖 AI','MATCH,DIRECT']
    }
  end
  def test_original_ai_nonai_and_credentials_preserved_only_one_probe_group_added
    before=source
    saved=Marshal.load(Marshal.dump(before))
    out,verdict=M.overlay(before)
    assert_equal 'PRIVATE_COPY_CANDIDATE',verdict
    assert_equal saved,before
    assert_equal saved['proxies'],out['proxies']
    assert_equal saved['rules'],out['rules']
    assert_equal saved['dns'],out['dns']
    assert_equal saved['secret'],out['secret']
    assert_equal saved['proxy-groups'],out['proxy-groups'][0...-1]
    assert_equal ['REJECT','TEST_0','TEST_1'],out['proxy-groups'][-1]['proxies']
    assert_equal [{ 'name'=>'ai-notebook-probe-only',
      'type'=>'http','listen'=>'127.0.0.1','port'=>17881,
      'proxy'=>'__AI_NOTEBOOK_PROBE_ONLY__' }],out['listeners']
    assert_equal out,Psych.safe_load(Psych.dump(out),aliases:false)
    refute_includes verdict,'SYNTHETIC_DO_NOT_PRINT'
  end
  def test_no_leaf_cap_and_existing_listener_preserved
    cfg=source
    2.upto(69) do |n|
      cfg['proxies'] << {'name'=>"TEST_#{n}",'type'=>'http','server'=>'192.0.2.1','port'=>8080}
    end
    cfg['listeners']=[{'name'=>'existing','type'=>'http','listen'=>'127.0.0.1','port'=>12345,'proxy'=>'DIRECT'}]
    out,verdict=M.overlay(cfg)
    assert_equal 'PRIVATE_COPY_CANDIDATE',verdict
    assert_equal 71,out['proxy-groups'][-1]['proxies'].length
    assert_equal cfg['listeners'],out['listeners'][0...-1]
    assert_equal cfg['proxy-groups'],out['proxy-groups'][0...-1]
  end
  def test_remote_dependencies_hold_before_any_copy_or_native_test
    variants={
      'HOLD_PROXY_PROVIDERS'=>proc { |s| s['proxy-providers']={'remote'=>{'type'=>'http','url'=>'https://example.invalid/proxies'}} },
      'HOLD_RULE_PROVIDERS'=>proc { |s| s['rule-providers']={'remote'=>{'type'=>'http','url'=>'https://example.invalid/rules'}} },
      'HOLD_SCRIPT_OR_EXTERNAL'=>proc { |s| s['external-ui-url']='https://example.invalid/ui' },
      'HOLD_GEO_RESOURCES'=>proc { |s| s['geodata-mode']=true },
      'HOLD_GEO_RESOURCES_RULE'=>proc { |s| s['rules']=['GEOSITE,google,🤖 AI','MATCH,DIRECT'] },
    }
    variants.each do |label,change|
      cfg=source
      change.call(cfg)
      out,status=M.overlay(cfg)
      assert_nil out
      expected=label=='HOLD_GEO_RESOURCES_RULE' ? 'HOLD_GEO_RESOURCES' : label
      assert_equal expected,status,label
      refute_includes status,'https://'
    end
  end
  def test_name_and_listener_conflicts_hold
    mutations={
      'HOLD_AI_PARENT'=>proc { |c| c['proxy-groups'][0]['type']='fallback' },
      'HOLD_DUPLICATE_LEAF'=>proc { |c| c['proxies'] << c['proxies'][0].dup },
      'HOLD_NAME_COLLISION'=>proc { |c| c['proxy-groups'] << {'name'=>'__AI_NOTEBOOK_PROBE_ONLY__','proxies'=>['DIRECT'],'type'=>'select'} },
      'HOLD_PORT'=>proc { |c| c['mixed-port']=17881 },
      'HOLD_LISTENER_COLLISION'=>proc { |c| c['listeners']=[{'name'=>'old','port'=>17881}] }
    }
    mutations.each do |status,change|
      cfg=source
      change.call(cfg)
      result,got=M.overlay(cfg)
      assert_nil result
      assert_equal status,got
    end
  end
  def test_temp_is_private_and_cleanup_symlinks_cannot_escape
    dir=M.folder
    refute_nil dir
    begin
      assert_equal 0700,(File.stat(dir).mode & 0777)
      File.write("#{dir}/config.yaml",Psych.dump(source))
      Dir.mkdir("#{dir}/cache",0700)
      File.symlink('/etc/passwd',"#{dir}/cache/not-followed")
      assert M.remove_folder(dir)
      refute File.exist?(dir)
      assert File.exist?('/etc/passwd')
      refute M.remove_folder('/etc')
      refute M.remove_folder('/tmp')
    ensure
      M.remove_folder(dir) if File.directory?(dir)
    end
  end
  def test_native_parse_child_only_returns_anonymous_pass_or_hold
    assert_equal 'PRIVATE_COPY_SYNTAX_PASS',
      M.native_test('/bin/sh','-c','exit 0',seconds:0.2) if false
    # Unlike the actual program, this uses a synthetic script as the
    # executable. Bad argv must fail anonymously without exposing path.
    x=M.native_test('/path/notfound','/tmp','/tmp/example.yaml',seconds:0.2)
    assert_equal 'HOLD_NATIVE_RUNTIME',x
    refute_includes x,'/tmp'
  end
  def test_device_script_minimal_runtime_and_no_production_writes
    src=File.read(File.expand_path('../scripts/ai_real_config_private_copy_native_gate.rb',__dir__))
    assert_equal ["require 'psych'"],src.lines.grep(/^require /).map(&:strip)
    assert_includes src,'SOURCE_CREDENTIALS=LOCAL_ONLY'
    assert_includes src,'PRODUCTION_CONFIG=UNCHANGED'
    assert_includes src,'LISTENER_INSTALLED=NO'
    refute_includes src,"require 'timeout'"
    refute_includes src,'/etc/init.d/openclash'
    refute_includes src,'requests.put('
    refute_includes src,'AI_ROUTE_UPDATED=YES'
  end
end
