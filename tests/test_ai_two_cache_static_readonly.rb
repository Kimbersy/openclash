require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../scripts/ai_two_cache_static_readonly'

class TwoCacheStaticTests < Minitest::Test
  G=AiTwoCacheStatic
  def setup
    @dir=Dir.mktmpdir('synthetic-two-cache-')
    Dir.mkdir(File.join(@dir,'rules'))
    @providers={}
    18.times do |i|
      rel="./rules/r#{i}.yaml"
      @providers["r#{i}"]={'type'=>'http','format'=>'yaml','behavior'=>'classical','path'=>rel,'url'=>"https://SYNTHETIC_SECRET@example.invalid/#{i}"}
      File.binwrite(File.join(@dir,rel),"payload:\n  - 'DOMAIN,example.invalid'\n")
    end
    @providers['large']={'type'=>'http','format'=>'yaml','behavior'=>'domain','path'=>'./rules/large.yaml','url'=>'https://example.invalid/large'}
    File.open(File.join(@dir,'rules/large.yaml'),'wb') {|f| f.write("payload:\n"); 52000.times {f.write("  - 'domain.example.invalid'\n")} }
    @providers['binary']={'type'=>'http','format'=>'mrs','behavior'=>'domain','path'=>'./rules/mrs.dat','url'=>'https://example.invalid/mrs'}
    File.binwrite(File.join(@dir,'rules/mrs.dat'), "MRS\x01".b+"not a verified body".b)
    @cfg={'geodata-mode'=>false,'geo-auto-update'=>false,'geox-url'=>{'geoip'=>'https://example.invalid/geo'},'rule-providers'=>@providers}
  end
  def teardown
    FileUtils.remove_entry(@dir)
  end
  def test_realistic_distribution_and_bounded_static_probe
    chosen,status=G.plan(@cfg,@dir)
    assert_equal 'TARGETS_IDENTIFIED',status
    assert_equal [:mrs,:yaml],chosen.keys.sort
    assert_operator chosen[:yaml][1].size,:>,G::ONE_MIB
    assert_equal 'YAML_SHALLOW_PASS',G.inspect_yaml(*chosen[:yaml])
    assert_equal 'MRS_V1_MAGIC_MATCH',G.inspect_mrs(*chosen[:mrs])
  end
  def test_mrs_wrong_version_or_short_magic_holds
    chosen,status=G.plan(@cfg,@dir)
    assert_equal 'TARGETS_IDENTIFIED',status
    path=chosen[:mrs][0]
    ["MRS\x02".b, 'MR'.b, 'NOTMRS'.b].each do |bad|
      File.binwrite(path,bad)
      stat=File.lstat(path)
      assert_equal 'HOLD_MRS_MAGIC_UNKNOWN',G.inspect_mrs(path,stat)
    end
  end
  def test_large_yaml_malformed_header_and_multiline_fails_closed
    chosen,status=G.plan(@cfg,@dir)
    assert_equal 'TARGETS_IDENTIFIED',status
    path=chosen[:yaml][0]
    File.open(path,'wb'){|f|f.write("unknown:\n");f.write("  - x\n"*450000)}
    assert_equal 'HOLD_YAML_LAYOUT',G.inspect_yaml(path,File.lstat(path))
    File.open(path,'wb'){|f|f.write("payload:\n  - a\n  nested: untrusted\n");f.write("  - x\n"*300000)}
    assert_equal 'HOLD_YAML_COMPLEX_LAYOUT',G.inspect_yaml(path,File.lstat(path))
  end
  def test_bounded_line_without_reading_large_line_into_memory
    path=File.join(@dir,'rules/large.yaml')
    File.open(path,'wb'){|f|f.write("payload:\n  - "+'x'*20000+"\n");f.write("  - x\n"*300000)}
    assert_equal 'HOLD_YAML_LINE_TOO_LONG',G.inspect_yaml(path,File.lstat(path))
  end
  def test_geo_snapshot_symlink_and_provider_change_hold
    @cfg['geo-auto-update']=true
    assert_equal 'HOLD_GEO_STATE_CHANGED',G.plan(@cfg,@dir)[1]
    @cfg['geo-auto-update']=false
    @providers['large']['path']='../../etc/shadow'
    assert_equal 'HOLD_PATH',G.plan(@cfg,@dir)[1]
    @providers['large']['path']='./rules/large.yaml'
    @providers['binary']['format']='text'
    assert_equal 'HOLD_SNAPSHOT_LAYOUT',G.plan(@cfg,@dir)[1]
  end
  def test_changed_inode_or_metadata_rejects
    chosen,status=G.plan(@cfg,@dir)
    assert_equal 'TARGETS_IDENTIFIED',status
    path,old=chosen[:mrs]
    File.binwrite(path,"MRS\x01X".b)
    assert_equal 'HOLD_FILE_CHANGED',G.inspect_mrs(path,old)
  end
  def test_no_extra_stdlib_and_no_network_or_mihomo_process
    s=File.read(File.join(__dir__,'../scripts/ai_two_cache_static_readonly.rb'))
    assert_equal ["require 'psych'"],s.scan(/^require ['"][^'"]+['"]$/)
    refute_match(/Process\.spawn|Process\.kill|IO\.popen|Net::HTTP|system\(/,s)
    assert_includes s,'NETWORK_ISOLATION=NOT_PROVEN'
    assert_includes s,'MRS_BINARY_CONTENT=NOT_PARSED'
    assert_includes s,'AUTO_SWITCH=OFF'
  end
end
