# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../scripts/ai_notebook_router_admission_readonly'

class TestAiNotebookRouterAdmission < Minitest::Test
  A = AiNotebookRouterAdmission
  def fixture
    {
      'proxies' => [
        {'name'=>'SYNTHETIC-01','type'=>'trojan','server'=>'example.invalid',
         'password'=>'SYNTHETIC_PRIVATE_NEVER_PRINT'}
      ],
      'proxy-groups' => [
        {'name'=>'🤖 AI','type'=>'select','proxies'=>['SYNTHETIC-01','DIRECT']},
        {'name'=>'🏰 Disney+','type'=>'select','proxies'=>['DIRECT']}
      ],
      'rules' => ['MATCH,🤖 AI'],
      'mixed-port' => 7890,
      'allow-lan'=>false,
      'secret'=>'PRIVATE_CONTROLLER_NOT_PRINTED'
    }
  end

  def proc_table(port, state='0A')
    hex = '%04X' % port
    "sl  local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode\n" \
      "0: 0100007F:#{hex} 00000000:0000 #{state} 0:0 0:0 00:00000000 0 0 0 0 10890\n"
  end

  def test_listening_port_detection_for_ipv4_and_ipv6
    a = proc_table(17_881)
    b = proc_table(18080)
    assert_includes A.listening_ports(a,b),17_881
    refute_includes A.listening_ports(a,b),7890
    refute_includes A.listening_ports(proc_table(17_881,'01'),b),17_881
    assert_nil A.listening_ports(nil,b)
    assert_nil A.listening_ports("header\n0: ??? 0000:0000 0A\n",b)
    assert_equal [], A.listening_ports("header\n","header\n")
  end

  def test_version_only_prints_semver_no_paths_or_secrets
    assert_equal '1.19.34', A.version_from_output("Mihomo Meta v1.19.34 linux amd64\n")
    assert_equal '1.19.12', A.version_from_output("mihomo version 1.19.12\n")
    assert_nil A.version_from_output("PRIVATE_SERVER=example.invalid")
    assert_nil A.version_from_output("x" * 4097)
  end

  def test_valid_running_config_eligible_only_for_private_copy
    cfg=fixture
    original=Marshal.load(Marshal.dump(cfg))
    status=A.config_assessment(cfg)
    assert_equal 'CONFIG_STRUCTURALLY_READY',status
    assert_equal original,cfg
    decision=A.overall(version:'1.19.34',ports:[],config_status:status)
    assert_equal 'READY_FOR_PRIVATE_COPY_NATIVE_TEST_ONLY',decision
    refute_includes decision,'SYNTHETIC-01'
    refute_includes decision,'PRIVATE_CONTROLLER'
  end

  def test_missing_core_version_or_unreadable_tcp_is_hold
    ['HOLD_CORE_VERSION_UNKNOWN','HOLD_LISTEN_PORT_UNKNOWN','HOLD_LISTEN_PORT_IN_USE'].zip([
      A.overall(version:nil, ports:[], config_status:'CONFIG_STRUCTURALLY_READY'),
      A.overall(version:'1.19.34',ports:nil,config_status:'CONFIG_STRUCTURALLY_READY'),
      A.overall(version:'1.19.34',ports:[17_881],config_status:'CONFIG_STRUCTURALLY_READY')
    ]).each { |expected,actual| assert_equal expected,actual }
  end

  def test_port_collision_in_original_config_fails_closed
    cfg=fixture
    cfg['mixed-port']=17_881
    assert_equal 'HOLD_CONFIG_PORT_COLLISION',A.config_assessment(cfg)
    cfg=fixture
    cfg['listeners']=[{'name'=>'existing','type'=>'http','port'=>17_881,'listen'=>'127.0.0.1'}]
    assert_equal 'HOLD_CONFIG_PORT_COLLISION',A.config_assessment(cfg)
    cfg=fixture
    cfg['listeners']=[{'name'=>'ai-notebook-probe-only','type'=>'http','port'=>18080,'listen'=>'127.0.0.1'}]
    assert_equal 'HOLD_PROBE_NAME_COLLISION',A.config_assessment(cfg)
  end

  def test_provider_mismatched_ai_parent_and_duplicate_leaf_fail_closed
    cfg=fixture
    cfg['proxy-providers']={'FUTURE'=>{'type'=>'http'}}
    assert_equal 'HOLD_SOURCE_PROVIDERS_PRESENT',A.config_assessment(cfg)
    cfg=fixture
    cfg['proxy-groups'][0]['type']='fallback'
    assert_equal 'HOLD_AI_PARENT_NOT_SELECT',A.config_assessment(cfg)
    cfg=fixture
    cfg['proxies'] << cfg['proxies'].first.dup
    assert_equal 'HOLD_DUPLICATE_OR_COLLIDING_NAMES',A.config_assessment(cfg)
    cfg=fixture
    cfg['proxy-groups'] << {'name'=>'SYNTHETIC-01','type'=>'select','proxies'=>['DIRECT']}
    assert_equal 'HOLD_DUPLICATE_OR_COLLIDING_NAMES',A.config_assessment(cfg)
    cfg=fixture
    cfg['proxy-groups'] << {'name'=>'__AI_NOTEBOOK_PROBE_ONLY__','type'=>'select','proxies'=>['DIRECT']}
    assert_equal 'HOLD_PROBE_NAME_COLLISION',A.config_assessment(cfg)
  end

  def test_ambiguous_existing_ports_fail_closed
    cfg=fixture
    cfg['socks-port']='7891-7899'
    assert_equal 'HOLD_UNKNOWN_CORE_PORT',A.config_assessment(cfg)
    cfg=fixture
    cfg['listeners']=[{'name'=>'old','port'=>'BAD:5678'}]
    assert_equal 'HOLD_UNVERIFIED_LISTENER',A.config_assessment(cfg)
  end

  def test_no_live_network_or_router_config_mutators_in_admission_script
    text=File.read(File.expand_path('../scripts/ai_notebook_router_admission_readonly.rb',__dir__))
    refute_includes text,'/etc/init.d/openclash'
    refute_includes text,'requests.put'
    refute_match(/^\s*(?:system|exec|spawn|Open3|Net::HTTP|curl)(?:\b|\()/, text)
    refute_includes text,'File.write('
    refute_includes text,'File.open('
    assert_includes text,'PRODUCTION_WRITES=NONE'
    assert_includes text,'PRIVATE_COPY_TEST=NOT_RUN'
  end
end
