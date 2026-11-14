require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../scripts/ai_rule_cache_byte_copy_gate'

class ByteCopyGateTests < Minitest::Test
  G = AiRuleCacheByteCopyGate
  def setup
    @temp = Dir.mktmpdir('fake-cache-')
    @home = File.join(@temp, 'home')
    @scratch = File.join(@temp, 'scratch')
    Dir.mkdir(@home)
    Dir.mkdir(@scratch)
    Dir.mkdir(File.join(@home,'rules'))
    @providers={}
    @n=20
    @n.times do |i|
      name="RULE#{i}"
      rel="./rules/r#{i}.yaml"
      @providers[name]={'type'=>'http', 'path'=>rel,'behavior'=>'classical','url'=>'https://example.invalid/x'}
      File.binwrite(File.join(@home,rel), "payload:\n  - 'DOMAIN,example.com'\n")
    end
    @cfg={'geodata-mode'=>false,'geo-auto-update'=>false, 'geox-url'=>{'mmdb'=>'https://example.invalid/geo'},'rule-providers'=>@providers}
  end
  def teardown
    FileUtils.remove_entry(@temp)
  end
  def test_twenty_local_byte_copies_verified_then_deleted
    src,st=G.catalog(@cfg,@home)
    assert_equal 'CATALOG_READY',st
    assert_equal 20,src.size
    result,count,clean=G.copy_and_compare(src,scratch_parent:@scratch)
    assert_equal ['BYTE_COPY_VERIFIED',20,'YES'], [result,count,clean]
    assert_equal [],Dir.children(@scratch)
  end
  def test_geo_custom_url_is_not_a_download_and_no_geo_updates
    src,st=G.catalog(@cfg,@home)
    assert_equal 'CATALOG_READY', st
    assert src
    @cfg['geo-auto-update']=true
    assert_equal 'HOLD_GEO_STATE_CHANGED',G.catalog(@cfg,@home)[1]
    @cfg['geo-auto-update']=false
    @cfg['geodata-mode']=true
    assert_equal 'HOLD_GEO_STATE_CHANGED',G.catalog(@cfg,@home)[1]
    @cfg['geodata-mode']=false
    @cfg.delete('geox-url')
    assert_equal 'HOLD_GEO_STATE_CHANGED',G.catalog(@cfg,@home)[1]
  end
  def test_symlink_and_outside_home_holds_before_read
    outside=File.join(@temp,'outside')
    File.binwrite(outside,'secret')
    first=@providers['RULE0']
    first['path']=outside
    assert_equal 'HOLD_PROVIDER_PATH',G.catalog(@cfg,@home)[1]
    first['path']='./rules/../x'
    assert_equal 'HOLD_PROVIDER_PATH',G.catalog(@cfg,@home)[1]
    first['path']='./rules/link.yaml'
    File.symlink(outside,File.join(@home,'rules','link.yaml'))
    assert_equal 'HOLD_PROVIDER_PATH',G.catalog(@cfg,@home)[1]
  end
  def test_missing_modified_and_duplicated_caches_hold
    src,st=G.catalog(@cfg,@home)
    assert_equal 'CATALOG_READY',st
    File.binwrite(src[0][0],'changed')
    result,count,clean=G.copy_and_compare(src,scratch_parent:@scratch)
    assert_equal ['HOLD_CACHE_CHANGED_OR_IO',0,'YES'],[result,count,clean]
    assert_equal [],Dir.children(@scratch)
    @providers['RULE1']['path']=@providers['RULE0']['path']
    assert_equal 'HOLD_DUPLICATE_CACHE',G.catalog(@cfg,@home)[1]
    @providers['RULE1']['path']='./rules/missing'
    assert_equal 'HOLD_CACHE_PATH_OR_ACCESS',G.catalog(@cfg,@home)[1]
  end
  def test_cache_budget_stops_oversized_file
    File.binwrite(File.join(@home,'rules/r0.yaml'),'x'*(G::MAX_FILE+1))
    assert_equal 'HOLD_CACHE_NOT_REGULAR',G.catalog(@cfg,@home)[1]
  end
  def test_only_psych_router_dependency_and_zero_remote_or_core_commands
    text=File.read(File.join(__dir__,'../scripts/ai_rule_cache_byte_copy_gate.rb'))
    assert_equal ["require 'psych'"],text.scan(/^require ['"][^'"]+['"]$/)
    refute_match(/Process\.spawn|open3|tempfile|net\/http/,text)
    assert_includes text, 'PRIVATE_CONFIG_TEST=NOT_RUN'
  end
end
