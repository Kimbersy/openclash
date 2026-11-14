require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../scripts/ai_rule_cache_structure_readonly'

class AiRuleCacheStructureTest < Minitest::Test
  G = AiRuleCacheStructureReadOnly
  def setup
    @root = Dir.mktmpdir('synthetic-static-rule-')
    Dir.mkdir(File.join(@root, 'cache'))
    @rule_providers = {}
    20.times do |i|
      name = "R_#{i}"
      path = "./cache/r#{i}.yaml"
      @rule_providers[name] = {
        'type' => 'http', 'path' => path,
        'url' => "https://SYNTHETIC_SECRET_NOT_FOR_LOG@invalid.example/#{i}",
        'behavior' => 'classical', 'format' => 'yaml'
      }
      File.binwrite(File.join(@root, path),
                    "payload:\n  - 'DOMAIN-SUFFIX,example.invalid'\n")
    end
    @config = {
      'rule-providers' => @rule_providers, 'geodata-mode' => false,
      'geo-auto-update' => false, 'geox-url' => {
        'geoip' => 'https://example.invalid/ip.dat'
      }
    }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def assert_class(result, yaml:, text:, mrs:)
    got, counts = G.classify(@config, @root)
    assert_equal result, got
    assert_equal yaml, counts['YAML']
    assert_equal text, counts['TEXT']
    assert_equal mrs, counts['MRS_UNPARSED']
    refute_includes [got, counts].inspect, 'SYNTHETIC_SECRET_NOT_FOR_LOG'
  end

  def test_20_yaml_caches_are_structurally_classified_without_mihomo
    assert_class('STATIC_STRUCTURE_PASS', yaml: 20, text: 0, mrs: 0)
  end

  def test_text_form_and_binary_mrs_are_not_misclassified
    @rule_providers['R_0']['format'] = 'text'
    File.binwrite(File.join(@root, 'cache/r0.yaml'),
                  "DOMAIN-SUFFIX,example.invalid\n# comment\n")
    assert_class('STATIC_STRUCTURE_PASS', yaml: 19, text: 1, mrs: 0)
    @rule_providers['R_1']['format'] = 'mrs'
    @rule_providers['R_1']['behavior'] = 'domain'
    File.binwrite(File.join(@root, 'cache/r1.yaml'), "\x00\x01\x02MRS".b)
    assert_class('HOLD_MRS_BINARY_UNPARSED', yaml: 18, text: 1, mrs: 1)
  end

  def test_invalid_yaml_binary_and_empty_text_hold
    f = File.join(@root, 'cache/r0.yaml')
    File.binwrite(f, 'payload: [}')
    assert_equal 'HOLD_YAML_PARSE', G.classify(@config, @root)[0]
    File.binwrite(f, "payload: 'not array'\n")
    assert_equal 'HOLD_YAML_LAYOUT', G.classify(@config, @root)[0]
    File.binwrite(f, "payload:\n  - abc\x00x\n")
    assert_equal 'HOLD_FILE_ENCODING', G.classify(@config, @root)[0]
    @rule_providers['R_0']['format'] = 'text'
    File.binwrite(f, "# comment only\n\n")
    assert_equal 'HOLD_TEXT_LAYOUT', G.classify(@config, @root)[0]
  end

  def test_existing_geo_state_preserved
    @config['geo-auto-update'] = true
    assert_equal 'HOLD_GEO_STATE_CHANGED', G.classify(@config, @root)[0]
    @config['geo-auto-update'] = false
    @config['geodata-mode'] = true
    assert_equal 'HOLD_GEO_STATE_CHANGED', G.classify(@config, @root)[0]
    @config['geodata-mode'] = false
    @config.delete('geox-url')
    assert_equal 'HOLD_GEO_STATE_CHANGED', G.classify(@config, @root)[0]
  end

  def test_escape_symlink_missing_and_snapshot_update_hold
    @rule_providers['R_0']['path'] = '/etc/passwd'
    assert_equal 'HOLD_CACHE_PATH', G.classify(@config, @root)[0]
    @rule_providers['R_0']['path'] = '../private'
    assert_equal 'HOLD_CACHE_PATH', G.classify(@config, @root)[0]
    @rule_providers['R_0']['path'] = './cache/link'
    File.symlink(File.join(@root, 'cache/r1.yaml'), File.join(@root, 'cache/link'))
    assert_equal 'HOLD_CACHE_PATH', G.classify(@config, @root)[0]
    @rule_providers['R_0']['path'] = './cache/not_found'
    assert_match(/\AHOLD_/, G.classify(@config, @root)[0])
    @rule_providers.delete('R_19')
    assert_equal 'HOLD_PROVIDER_COUNT_CHANGED', G.classify(@config, @root)[0]
  end

  def test_limits_and_unexpected_formats_hold
    @rule_providers['R_0']['format'] = 'mrs'
    assert_equal 'HOLD_MRS_BEHAVIOR', G.classify(@config, @root)[0]
    @rule_providers['R_0']['format'] = 'unknown'
    assert_equal 'HOLD_FILE_FORMAT', G.classify(@config, @root)[0]
    @rule_providers['R_0']['format'] = 'yaml'
    @rule_providers['R_0']['behavior'] = 'invalid'
    assert_equal 'HOLD_BEHAVIOR', G.classify(@config, @root)[0]
    @rule_providers['R_0']['behavior'] = 'classical'
    File.binwrite(File.join(@root, 'cache/r0.yaml'), 'x' * (G::MAX_FILE + 1))
    assert_equal 'HOLD_FILE_SIZE', G.classify(@config, @root)[0]
  end

  def test_minimal_router_runtime_no_side_effects
    script = File.read(File.join(__dir__, '../scripts/ai_rule_cache_structure_readonly.rb'))
    assert_equal ["require 'psych'"], script.scan(/^require ['"][^'"]+['"]$/)
    refute_match(/Process\.spawn|Process\.kill|Net::HTTP|IO\.popen|system\(/, script)
    assert_includes script, 'MIHOMO_SYNTAX=NOT_VALIDATED'
    assert_includes script, 'NETWORK_ISOLATION=NOT_PROVEN'
    assert_includes script, 'AUTO_SWITCH=OFF'
  end
end
