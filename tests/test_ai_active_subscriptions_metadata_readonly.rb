require 'minitest/autorun'
require_relative '../scripts/ai_active_subscriptions_metadata_readonly'

class AiActiveSubscriptionsMetadataReadOnlyTests < Minitest::Test
  G=AiActiveSubscriptionsMetadataReadOnly

  def sample
    <<~UCI
      openclash.config=openclash
      openclash.config.config_path='/etc/openclash/config/PRIVATE.yaml'
      openclash.config.auto_update='1'
      openclash.config.config_auto_update_mode='0'
      openclash.config.config_update_week_time='*'
      openclash.@config_subscribe[0]=config_subscribe
      openclash.@config_subscribe[0].enabled='1'
      openclash.@config_subscribe[0].address='https://PRIVATE:TOKEN@example.invalid/x'
      openclash.@config_subscribe[0].name='PRIVATE AIRPORT'
      openclash.cfg12345=config_subscribe
      openclash.cfg12345.enabled='1'
      openclash.cfg12345.address='https://private-other.invalid/?secret=abc'
      openclash.cfg99999=config_subscribe
      openclash.cfg99999.enabled='0'
      openclash.cfg99999.address='https://disabled.invalid'
      openclash.config.secret='PRIVATE_CONTROLLER_SECRET'
      openclash.config.password='PRIVATE_PASSWORD'
    UCI
  end

  def test_exact_two_enabled_one_disabled_and_no_secrets_or_urls
    m,code=G.parse_uci(sample)
    assert_equal 'UCI_ENABLED_SOURCE_METADATA_CLASSIFIED',code
    assert_equal 3,m['UCI_SUBSCRIPTION_SECTION_COUNT']
    assert_equal 2,m['UCI_EXPLICIT_ENABLED_COUNT']
    assert_equal 1,m['UCI_EXPLICIT_DISABLED_COUNT']
    assert_equal 0,m['UCI_ENABLE_FLAG_UNKNOWN_COUNT']
    assert_equal 0,m['UCI_ENABLED_ADDRESS_MISSING_COUNT']
    assert_equal 'YES',m['UCI_SELECTED_CONFIG_DECLARED']
    assert_equal 'ENABLED',m['UCI_AUTO_UPDATE']
    assert_equal 'DAILY',m['UCI_UPDATE_CADENCE']
    %w[PRIVATE TOKEN example.invalid PRIVATE_CONTROLLER_SECRET PRIVATE_PASSWORD cfg12345].each do |secret|
      refute_includes m.inspect,secret
    end
  end

  def test_missing_enabled_is_unknown_not_default_enabled
    uci="openclash.@config_subscribe[0]=config_subscribe\n"+
      "openclash.@config_subscribe[0].address='https://secret.invalid'\n"
    m,result=G.parse_uci(uci)
    assert_equal 'HOLD_UCI_SUBSCRIPTION_STATUS_AMBIGUOUS',result
    assert_equal 0,m['UCI_EXPLICIT_ENABLED_COUNT']
    assert_equal 1,m['UCI_ENABLE_FLAG_UNKNOWN_COUNT']
  end

  def test_address_missing_blocks_enabled_source
    uci="openclash.cfg1=config_subscribe\nopenclash.cfg1.enabled='1'\n"
    m,result=G.parse_uci(uci)
    assert_equal 'HOLD_NO_CONFIRMED_ENABLED_SOURCE',result
    assert_equal 1,m['UCI_ENABLED_ADDRESS_MISSING_COUNT']
  end

  def test_conflicting_flags_or_different_value_hold
    uci="openclash.cfg1=config_subscribe\nopenclash.cfg1.enabled='1'\n"+
      "openclash.cfg1.enable='0'\nopenclash.cfg1.address='private'\n"
    m,result=G.parse_uci(uci)
    assert_equal 'HOLD_UCI_SUBSCRIPTION_STATUS_AMBIGUOUS',result
    assert_equal 1,m['UCI_ENABLE_FLAG_CONFLICT_COUNT']
    refute_includes m.inspect,'private'
  end

  def test_duplicate_section_or_orphan_flag_blocks
    uci="openclash.cfg1=config_subscribe\nopenclash.cfg1=config_subscribe\n"
    assert_equal 'HOLD_DUPLICATE_SOURCE_SECTION',G.parse_uci(uci).last
    uci="openclash.cfg1=config_subscribe\nopenclash.cfg1.enabled='1'\n"+
      "openclash.cfg1.address='secret'\nopenclash.cfg2.enabled='1'\n"
    m,result=G.parse_uci(uci)
    assert_equal 'HOLD_UCI_SUBSCRIPTION_STATUS_AMBIGUOUS',result
    assert_equal 1,m['UCI_ORPHAN_OPTION_BUCKETS']
  end

  def test_loop_cadence_weekly_and_auto_update_disabled
    s=sample.sub("config_auto_update_mode='0'","config_auto_update_mode='1'").
      sub("config_update_week_time='*'","config_update_interval='45'")
    m,status=G.parse_uci(s)
    assert_equal 'UCI_ENABLED_SOURCE_METADATA_CLASSIFIED',status
    assert_equal 'PERIODIC',m['UCI_UPDATE_CADENCE']
    s=sample.sub("config_update_week_time='*'","config_update_week_time='3'")
    assert_equal 'WEEKLY',G.parse_uci(s).first['UCI_UPDATE_CADENCE']
    s=sample.sub("auto_update='1'","auto_update='0'")
    assert_equal 'DISABLED',G.parse_uci(s).first['UCI_AUTO_UPDATE']
  end

  def test_no_sections_and_unknown_refresh_does_not_claim_success
    m,result=G.parse_uci("openclash.config.auto_update='1'\n")
    assert_equal 'HOLD_NO_CONFIG_SUBSCRIBE_SECTIONS',result
    assert_equal 0,m['UCI_SUBSCRIPTION_SECTION_COUNT']
    assert_equal 'UNKNOWN',m['UCI_UPDATE_CADENCE']
    assert_equal 'HOLD_UCI_SIZE',G.parse_uci('').last
    assert_equal 'HOLD_UCI_SIZE',G.parse_uci('x'*(G::MAX_UCI_BYTES+1)).last
  end

  def test_minimal_device_runtime_no_http_no_credentials_printed
    code=File.read(File.join(__dir__,'../scripts/ai_active_subscriptions_metadata_readonly.rb'))
    assert_equal [],code.scan(/^require ['"][^'"]+['"]$/)
    assert_includes code,"'uci','-q','show','openclash'"
    assert_includes code,'HTTP=NOT_REQUESTED'
    assert_includes code,'ENABLED_SUBSCRIPTION_MERGE_PROVENANCE=NOT_VERIFIED'
    assert_includes code,'REMOTE_SUBSCRIPTION_REFRESH_SUCCESS=NOT_VERIFIED'
    assert_includes code,'SUBSCRIPTION_NAMES_URLS_AND_SECRETS=NOT_EMITTED'
    refute_match(/Net::HTTP|curl|Process\.spawn|require_relative|system\(|\.write\(/,code)
    assert_includes code,'AUTO_SWITCH=OFF'
  end
end
