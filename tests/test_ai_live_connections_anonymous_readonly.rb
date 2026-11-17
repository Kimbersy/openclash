require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require_relative '../scripts/ai_runtime_leaf_inventory_readonly'

class AiLiveConnectionsAnonymousReadOnlyTests < Minitest::Test
  G=AiRuntimeLeafNamesReadOnly
  SOURCE='192.168.42.23'
  LEAF='SECRET_LEAF_PRIVATE_NAME_DO_NOT_PRINT'
  OTHER='SECOND_PRIVATE_LEAF'
  SERVICES={'CHATGPT'=>'chatgpt.com',
            'GEMINI'=>'gemini.google.com',
            'NOTEBOOKLM'=>'notebooklm.google.com'}.freeze

  def expected
    {'leaves'=>[LEAF,OTHER],'groups'=>['🤖 AI','OTHER']}
  end

  def row(service, leaf:LEAF,source:SOURCE,host:nil,sniff:nil,chain:nil)
    metadata={'sourceIP'=>source,'host'=>host || SERVICES.fetch(service)}
    metadata['sniffHost']=sniff unless sniff.nil?
    {'metadata'=>metadata,'chains'=>chain || [leaf,'🤖 AI'],
     'id'=>'PRIVATE-CONNECTION-ID', 'processPath'=>'PRIVATE-USER-PATH'}
  end

  def all_three
    SERVICES.keys.map{|svc|row(svc)}
  end

  def classify(items,source=SOURCE)
    G.private_connection_classification(expected,{'connections'=>items},source)
  end

  def capture
    old=$stdout
    out=StringIO.new
    $stdout=out
    yield
    out.string
  ensure
    $stdout=old
  end

  def test_private_source_only_and_exact_host_matching
    assert G.allowed_source_ipv4?(SOURCE)
    assert G.allowed_source_ipv4?('10.1.2.3')
    assert G.allowed_source_ipv4?('172.31.1.1')
    assert G.allowed_source_ipv4?('100.64.0.1')
    %w[127.0.0.1 8.8.8.8 192.168.1.0x1 192.168.01.1
       192.168.1 172.32.0.1 0.0.0.0 2001:db8::1].each do |ip|
      refute G.allowed_source_ipv4?(ip),ip
    end
    assert_equal 'CHATGPT',G.target_service('API.ChatGPT.Com.')
    assert_equal 'GEMINI',G.target_service('gemini.google.com')
    assert_equal 'NOTEBOOKLM',G.target_service('notebooklm.google.com')
    %w[gemini.google.com.evil.com othergemini.google.com
       notebooklm.google.com.attacker.chatgpt.com.evil.net
       fakechatgpt.com google.com].each do |host|
      assert_nil G.target_service(host),host
    end
    assert_nil G.target_service('gemini.google.com:443')
  end

  def test_three_ai_services_same_one_leaf_is_candidate_not_credentials
    result,gate=classify(all_three)
    assert_equal 'ANONYMOUS_CLASSIFICATION_READY',gate
    assert_equal 'SAME_LEAF_ANONYMOUS_CANDIDATE_ONLY',result[:result]
    assert_equal 3,result[:status].count{|_,v|v=='OBSERVED_ONE_LEAF_CANDIDATE'}
    refute_includes result.inspect,'PRIVATE-CONNECTION-ID'
  end

  def test_multiple_leaves_across_services_fail_closed
    rows=all_three
    rows[2]=row('NOTEBOOKLM',leaf:OTHER)
    result,_=classify(rows)
    assert_equal 'HOLD_DIFFERENT_SERVICE_LEAVES',result[:result]
    assert_equal 'OBSERVED_ONE_LEAF_CANDIDATE',result[:status]['NOTEBOOKLM']
    rows=all_three + [row('CHATGPT',leaf:OTHER)]
    result,_=classify(rows)
    assert_equal 'HOLD_MULTIPLE_LEAVES',result[:status]['CHATGPT']
    assert_equal 'HOLD_INCOMPLETE_SAME_LEAF_EVIDENCE',result[:result]
  end

  def test_direct_bypass_unknown_proxy_group_and_ambiguous_leaf_hold
    for chain in [['DIRECT','🤖 AI'],[LEAF,'OTHER'],
                  [LEAF,OTHER,'🤖 AI'],['UNKNOWN_LEAF','🤖 AI'],
                  [LEAF,LEAF,'🤖 AI'],nil,[]]
      rows=all_three
      rows[0]=row('CHATGPT',chain:chain) if chain
      rows[0]['chains']=nil unless chain
      result,_=classify(rows)
      assert_equal 'HOLD_AMBIGUOUS_CONNECTION',result[:status]['CHATGPT'],chain.inspect
      assert_equal 'HOLD_INCOMPLETE_SAME_LEAF_EVIDENCE',result[:result]
    end
  end

  def test_other_household_users_and_unseen_service_cannot_be_used
    others=SERVICES.keys.map{|svc|row(svc,source:'192.168.42.55')}
    result,_=classify(others)
    assert result[:status].values.all?{|v|v=='HOLD_NO_ACTIVE_CONNECTION'}
    result,_=classify([row('CHATGPT')]+others)
    assert_equal 'OBSERVED_ONE_LEAF_CANDIDATE',result[:status]['CHATGPT']
    assert_equal 'HOLD_NO_ACTIVE_CONNECTION',result[:status]['GEMINI']
    assert_equal 'HOLD_INCOMPLETE_SAME_LEAF_EVIDENCE',result[:result]
    result,gate=classify(all_three,'8.8.8.8')
    assert_nil result
    assert_equal 'HOLD_SOURCE_NOT_PRIVATE_IPV4',gate
  end

  def test_sniffhost_disagreement_and_domain_spoof_is_hold
    rows=all_three
    rows[0]=row('CHATGPT',sniff:'gemini.google.com')
    result,_=classify(rows)
    assert_equal 'HOLD_AMBIGUOUS_CONNECTION',result[:status]['CHATGPT']
    assert_equal 'HOLD_AMBIGUOUS_CONNECTION',result[:status]['GEMINI']
    rows=all_three
    rows[0]=row('CHATGPT',sniff:'not-chatgpt.example')
    result,_=classify(rows)
    assert_equal 'HOLD_AMBIGUOUS_CONNECTION',result[:status]['CHATGPT']
    rows=all_three
    rows[0]['metadata']['sniffHost']={'untrusted'=>'fake'}
    result,_=classify(rows)
    assert_equal 'HOLD_AMBIGUOUS_CONNECTION',result[:status]['CHATGPT']
    rows=all_three
    rows[1]['metadata']['host']='gemini.google.com.attacker.tld'
    result,_=classify(rows)
    assert_equal 'HOLD_NO_ACTIVE_CONNECTION',result[:status]['GEMINI']
  end

  def test_fail_closed_malformed_input_and_no_ai_parent
    result,gate=G.private_connection_classification(expected,{'connections'=>[]},SOURCE)
    assert_equal 'ANONYMOUS_CLASSIFICATION_READY',gate
    assert_equal 'HOLD_INCOMPLETE_SAME_LEAF_EVIDENCE',result[:result]
    result,gate=G.private_connection_classification(expected,{'connections'=>'not an array'},SOURCE)
    assert_nil result
    assert_equal 'HOLD_CONNECTIONS_LAYOUT',gate
    result,gate=G.private_connection_classification(
      {'leaves'=>[LEAF], 'groups'=>['OTHER']},{'connections'=>all_three},SOURCE)
    assert_nil result
    assert_equal 'HOLD_EXPECTED_LAYOUT',gate
    result,gate=classify(all_three+[{'metadata'=>nil,'chains'=>[LEAF,'🤖 AI']}])
    assert_nil result
    assert_equal 'HOLD_CONNECTIONS_LAYOUT',gate
    result,gate=classify(all_three+[{'random'=>'invalid'}])
    assert_nil result
    assert_equal 'HOLD_CONNECTIONS_LAYOUT',gate
    result,gate=G.private_connection_classification(
      expected,{'connections'=>Array.new(G::MAX_ACTIVE_CONNECTIONS+1)},SOURCE)
    assert_nil result
    assert_equal 'HOLD_CONNECTIONS_LAYOUT',gate
  end

  def test_live_mode_prints_only_bounded_enums_even_with_private_data
    Dir.mktmpdir do |dir|
      path=File.join(dir,'current.yaml')
      data={'proxies'=>[LEAF,OTHER].map{|n|{'name'=>n,'type'=>'ss',
        'password'=>'SECRET_PASSWORD_NEVER_PRINT'}},
        'proxy-groups'=>[{'name'=>'🤖 AI','type'=>'select','proxies'=>[LEAF]},
                         {'name'=>'OTHER','type'=>'select','proxies'=>[OTHER]}]}
      File.binwrite(path,Psych.dump(data))
      api={'proxies'=>{'🤖 AI'=>{'type'=>'Selector'},'OTHER'=>{'type'=>'Selector'},
        LEAF=>{'type'=>'Shadowsocks'},OTHER=>{'type'=>'Shadowsocks'}}}
      response={'connections'=>all_three}
      out=G.stub(:candidate_core,['1357',[],path]) do
        G.stub(:controller_port,6161) do
          G.stub(:core_process_identity,['exe','net','tick']) do
            G.stub(:listener_evidence,['IPV4_CORE_SOCKET',['999']]) do
              G.stub(:api_read,api) do
                G.stub(:active_connections_read,response) do
                  capture{G.run_connections(SOURCE)}
                end
              end
            end
          end
        end
      end
      assert_includes out,'AI_FLOW_RESULT=SAME_LEAF_ANONYMOUS_CANDIDATE_ONLY'
      assert_includes out,'AI_FLOW_GEMINI=OBSERVED_ONE_LEAF_CANDIDATE'
      assert_includes out,'ALLOW_RECONCILE=NO ALLOW_SWITCH=NO'
      for secret in [LEAF,OTHER,'SECRET_PASSWORD_NEVER_PRINT',SOURCE,
                     'chatgpt.com','gemini.google.com','notebooklm.google.com',
                     'PRIVATE-CONNECTION-ID','PRIVATE-USER-PATH']
        refute_includes out,secret
      end
    end
  end

  def test_owner_unknown_blocks_request_before_any_controller_http
    out=G.stub(:candidate_core,nil) {capture{G.run_connections(SOURCE)}}
    assert_includes out,'HOLD_CORE_NOT_UNIQUE'
    refute_includes out,'AI_FLOW_CHATGPT=OBSERVED'
    cmd=File.expand_path('../scripts/ai_runtime_leaf_inventory_readonly.rb',__dir__)
    output=IO.popen(['ruby',cmd,'--connections-source','8.8.8.8'],err:File::NULL,&:read)
    assert_includes output,'HOLD_SOURCE_NOT_PRIVATE_IPV4'
    assert_includes output,'PRIVATE_SOURCE_HOSTS_LEAVES_CHAINS_AND_RAW_JSON=NOT_EMITTED'
  end

  def test_single_file_real_device_dependencies_and_transport_only_get
    text=File.binread(File.expand_path('../scripts/ai_runtime_leaf_inventory_readonly.rb',__dir__))
    assert_equal ["require 'psych'"],text.scan(/^require ['"][^'"]+['"]$/)
    assert_includes text,'http://127.0.0.1:#{port}/connections'
    assert_includes text,"'--request','GET'"
    assert_includes text,"'--ipv4','--noproxy','*'"
    assert_includes text,'identity==core_process_identity(pid)'
    assert_includes text,'candidate_core==core'
    assert_includes text,'owner==listener_evidence(pid,port)'
    assert_includes text,"coverage_status=='LIVE_LEAF_NAME_COVERAGE_PASS'"
    assert_includes text,'SAME_LEAF_AUTHENTICATED=NO'
    refute_match(/https?:\/\/(?!127\.0\.0\.1)|Net::HTTP|require_relative|Process\.spawn|--request','PUT|--request','DELETE/,text)
  end
end
