require 'minitest/autorun'
require_relative '../scripts/ai_controller_socket_diagnostic_readonly'

class SocketOwnerDiagnosticTests < Minitest::Test
  G=AiControllerSocketDiagnostic
  def row(ip,port,ino,status='0A')
    "  0: #{ip}:#{format('%04X',port)} 00000000:0000 #{status} 00000000:00000000 00:00000000 00000000 0 0 #{ino} 1 0000000000000000 100 0 0 10 0"
  end

  def test_ipv4_loopback_ipv4_wildcard_ipv6_and_other_classify_without_disclosure
    port=9911
    lines=[row('0100007F',port,'12345'),row('00000000',port,'12346'),
           row('0100000A',port,'12347'),row('0100007F',port+1,'88888'),
           row('0100007F',port,'77777','01')]
    v4,status=G.socket_rows(lines,port)
    assert_equal 'OK',status
    assert_equal %w[IPV4_LOOPBACK IPV4_WILDCARD IPV4_OTHER],v4.map(&:first)
    v6,sv6=G.socket_rows([row('00000000000000000000000000000000',port,'12348')],port,ipv6:true)
    assert_equal 'OK',sv6
    data=G.owner_diagnosis(v4,v6,{'12345'=>true,'12348'=>true})
    assert_equal 'IPV4_CORE_SOCKET',data['OWNER_EVIDENCE']
    assert_equal 1,data['TCP4_PORT_LOOPBACK']
    assert_equal 1,data['TCP4_PORT_WILDCARD']
    assert_equal 1,data['TCP4_PORT_OTHER']
    assert_equal 1,data['TCP6_PORT_LISTEN']
    assert_equal 2,data['CORE_FD_PORT_MATCH']
    refute_includes data.inspect,'0100000A'
    refute_includes data.inspect,'12345'
  end

  def test_ipv6_only_and_unmatched_and_no_listener_distinguished
    v6=[['IPV6','200']]
    assert_equal 'IPV6_CORE_SOCKET_ONLY',
      G.owner_diagnosis([],v6,{'200'=>true})['OWNER_EVIDENCE']
    assert_equal 'LISTENER_NOT_MATCHED_TO_CORE_FD',
      G.owner_diagnosis([['IPV4_WILDCARD','300']],[],{})['OWNER_EVIDENCE']
    assert_equal 'NO_LISTENER_AT_PORT',
      G.owner_diagnosis([],[],{})['OWNER_EVIDENCE']
    assert_nil G.owner_diagnosis(nil,[],{})
  end

  def test_other_ip_socket_ownership_not_treated_as_loopback_compatible
    v4=[['IPV4_OTHER','900']]
    assert_equal 'LISTENER_NOT_MATCHED_TO_CORE_FD',
      G.owner_diagnosis(v4,[],{'900'=>true})['OWNER_EVIDENCE']
    assert_equal 1,G.owner_diagnosis(v4,[],{'900'=>true})['CORE_FD_PORT_MATCH']
  end

  def test_controller_rejects_remote_and_only_accepted_loopback_bind
    assert_equal 9090,G.controller_port('127.0.0.1:9090')
    assert_equal 9090,G.controller_port('0.0.0.0:9090')
    assert_equal 'IPV4_LOOPBACK',G.bind_class('127.0.0.1:9090')
    assert_equal 'IPV4_WILDCARD',G.bind_class('0.0.0.0:9090')
    %w[localhost:9090 10.0.0.1:9090 [::]:9090 127.0.0.1:0].each do |invalid|
      assert_nil G.controller_port(invalid)
    end
  end

  def test_budget_and_malformed_lines_fail_closed
    old=G::PROC_LINES_LIMIT
    G.send(:remove_const,:PROC_LINES_LIMIT)
    G.const_set(:PROC_LINES_LIMIT,2)
    rows,status=G.socket_rows(['x','x','x'],9090)
    assert_nil rows
    assert_equal 'HOLD_PROC_LINES_BUDGET',status
  ensure
    G.send(:remove_const,:PROC_LINES_LIMIT)
    G.const_set(:PROC_LINES_LIMIT,old)
  end

  def test_no_network_core_invocation_or_unverified_ruby_imports
    s=File.read(File.join(__dir__,'../scripts/ai_controller_socket_diagnostic_readonly.rb'))
    assert_equal ["require 'psych'"],s.scan(/^require ['"][^'"]+['"]$/)
    refute_match(/IO\.popen|Process\.spawn|Net::HTTP|system\(|require_relative|Timeout\./,s)
    refute_match(/\/providers\/rules|Authorization:|Bearer /,s)
    assert_includes s,'CONTROLLER_HTTP=NOT_REQUESTED'
    assert_includes s,'PROVIDER_REFRESH=NOT_RUN'
    assert_includes s,'AUTO_SWITCH=OFF'
  end
end
