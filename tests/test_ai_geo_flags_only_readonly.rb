# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../scripts/ai_geo_flags_only_readonly'

class TestGeoFlagsOnly < Minitest::Test
  M=AiGeoFlagOnly

  def test_actual_old_flag_is_union_not_inference_of_auto_update
    [
      [{ 'geodata-mode'=>true }, 'TRUE', 'FALSE', 'ABSENT'],
      [{ 'geo-auto-update'=>true }, 'FALSE', 'TRUE', 'ABSENT'],
      [{ 'geox-url'=>{'geoip'=>'https://PRIVATE_KEY.example.invalid'} }, 'FALSE', 'FALSE', 'PRESENT'],
      [{ 'geodata-mode'=>false, 'geo-auto-update'=>false }, 'FALSE','FALSE','ABSENT'],
      [{ 'geodata-mode'=>true, 'geo-auto-update'=>false, 'geox-url'=>{} }, 'TRUE','FALSE','PRESENT']
    ].each do |input, dat, refresh, url|
      output=M.summary(input)
      assert_equal dat,output['GEO_DAT_MODE']
      assert_equal refresh,output['GEO_AUTO_UPDATE']
      assert_equal url,output['GEO_CUSTOM_URL']
      refute_includes output.inspect,'PRIVATE_KEY'
    end
  end

  def test_malformed_values_do_not_silently_pass_as_false
    out=M.summary({'geodata-mode'=>'yes','geo-auto-update'=>'yes'})
    assert_equal 'UNRECOGNIZED',out['GEO_DAT_MODE']
    assert_equal 'UNRECOGNIZED',out['GEO_AUTO_UPDATE']
    assert_nil M.summary(nil)
  end

  def test_stock_router_runtime_no_unverified_stdlib_or_side_effect
    file=File.expand_path('../scripts/ai_geo_flags_only_readonly.rb',__dir__)
    src=File.read(file)
    assert_equal ["require 'psych'"],src.lines.grep(/^require /).map(&:strip)
    assert_includes src,'RULE_PROVIDER_CACHES=NOT_READ'
    assert_includes src,'PRIVATE_COPY_TEST=NOT_RUN'
    assert_includes src,'PRODUCTION_CONFIG=UNCHANGED'
    refute_includes src,'require "timeout"'
    refute_includes src,'Process.spawn('
    refute_includes src,'File.write('
    refute_includes src,'system('
    refute_includes src,'curl '
  end
end
