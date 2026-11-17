require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../scripts/ai_rule_cache_size_profile_readonly'

class AiRuleCacheSizeProfileTest < Minitest::Test
  G = AiRuleCacheSizeProfile
  def setup
    @dir = Dir.mktmpdir('synthetic-cache-size-')
    Dir.mkdir(File.join(@dir, 'rules'))
    @providers = {}
    20.times do |i|
      @providers["rule#{i}"] = {
        'type' => 'http', 'path' => "./rules/r#{i}.yaml",
        'format' => 'yaml', 'behavior' => 'classical',
        'url' => "https://SECRET_MUST_NOT_LEAK@invalid.example/#{i}"
      }
      File.binwrite(File.join(@dir, "rules/r#{i}.yaml"), 's' * 20)
    end
    @cfg = {
      'rule-providers' => @providers,
      'geodata-mode' => false, 'geo-auto-update' => false,
      'geox-url' => {'geoip' => 'https://invalid.example/private'}
    }
  end
  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_all_twenty_including_late_oversize_yaml_classified_without_content_reads
    [18, 19].each do |i|
      File.binwrite(File.join(@dir, "rules/r#{i}.yaml"), 'x' * (G::SMALL_YAML + 1))
    end
    status, c = G.profile(@cfg, @dir)
    assert_equal 'SIZE_FORMAT_CLASSIFIED', status
    assert_equal 20, c['FORMAT_YAML']
    assert_equal 18, c['YAML_LE_1M']
    assert_equal 2, c['YAML_GT_1M']
    assert_equal 2, c['ALL_GT_1M']
    assert_equal 0, c['ALL_GT_4M']
    refute_includes c.inspect, 'SECRET_MUST_NOT_LEAK'
  end

  def test_mixed_late_formats_are_not_assumed_to_be_yaml
    @providers['rule19']['format'] = 'mrs'
    @providers['rule19']['behavior'] = 'domain'
    @providers['rule18']['format'] = 'text'
    status, c = G.profile(@cfg, @dir)
    assert_equal 'SIZE_FORMAT_CLASSIFIED', status
    assert_equal [18, 1, 1], c.values_at('FORMAT_YAML', 'FORMAT_TEXT', 'FORMAT_MRS')
    assert_equal 0, c['YAML_GT_1M']
  end

  def test_missing_symlink_escape_and_duplicate_hold
    @providers['rule0']['path'] = '/etc/passwd'
    assert_equal 'HOLD_PATH', G.profile(@cfg, @dir).first
    @providers['rule0']['path'] = '../secret'
    assert_equal 'HOLD_PATH', G.profile(@cfg, @dir).first
    @providers['rule0']['path'] = './rules/alias'
    File.symlink(File.join(@dir, 'rules/r1.yaml'), File.join(@dir, 'rules/alias'))
    assert_equal 'HOLD_PATH', G.profile(@cfg, @dir).first
    @providers['rule0']['path'] = @providers['rule1']['path']
    assert_equal 'HOLD_DUPLICATE_PATH', G.profile(@cfg, @dir).first
    @providers['rule0']['path'] = './rules/missing.yaml'
    assert_equal 'HOLD_FILESYSTEM', G.profile(@cfg, @dir).first
  end

  def test_file_size_limits_and_changed_provider_count_hold
    File.binwrite(File.join(@dir, 'rules/r0.yaml'), 'x' * (G::MAX_FILE + 1))
    assert_equal 'HOLD_FILE', G.profile(@cfg, @dir).first
    @providers.delete('rule19')
    assert_equal 'HOLD_SOURCE_COUNT_CHANGED', G.profile(@cfg, @dir).first
  end

  def test_provider_and_geo_layout_fail_closed
    @cfg['geo-auto-update'] = true
    assert_equal 'HOLD_GEO_STATE_CHANGED', G.profile(@cfg, @dir).first
    @cfg['geo-auto-update'] = false
    @cfg['geodata-mode'] = true
    assert_equal 'HOLD_GEO_STATE_CHANGED', G.profile(@cfg, @dir).first
    @cfg['geodata-mode'] = false
    @cfg.delete('geox-url')
    assert_equal 'HOLD_GEO_STATE_CHANGED', G.profile(@cfg, @dir).first
    @cfg['geox-url'] = {}
    @providers['rule0']['format'] = 'invalid'
    assert_equal 'HOLD_PROVIDER_FORMAT', G.profile(@cfg, @dir).first
  end

  def test_dependency_and_no_content_access_contract
    src = File.read(File.join(__dir__, '../scripts/ai_rule_cache_size_profile_readonly.rb'))
    assert_equal ["require 'psych'"], src.scan(/^require ['"][^'"]+['"]$/)
    refute_match(/Process\.spawn|Net::HTTP|IO\.popen|system\(/, src)
    assert_includes src, 'CACHE_CONTENT=NOT_READ'
    assert_includes src, 'MIHOMO_SYNTAX=NOT_VALIDATED NETWORK_ISOLATION=NOT_PROVEN'
    assert_includes src, 'LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
  end
end
