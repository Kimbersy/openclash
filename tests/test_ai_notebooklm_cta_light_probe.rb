# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../scripts/ai_notebooklm_cta_light_probe'

class NotebookCtaLightweightTest < Minitest::Test
  def classify(final:, code: '200', locations: [], rc: 0)
    headers = locations.map { |url| "HTTP/2 302\r\nlocation: #{url}\r\n\r\n" }.join
    NotebookCtaLite.classify(
      curl_rc: rc, http_code: code, headers: headers, effective: final
    )
  end

  def test_user_supported_cta_url_is_only_app_candidate_not_success
    result = classify(final: 'https://notebook.google.com/?icid=home_maincta')
    assert_equal 'LIGHT_APP_HTTP_CANDIDATE_UNVERIFIED', result
    refute_equal 'BUSINESS_VERIFIED', result
  end

  def test_unsupported_from_real_redirect_hops_wins_over_marketing_http_200
    assert_equal 'LIGHT_UNSUPPORTED_OBSERVED', classify(
      final: 'https://notebook.google/',
      locations: ['https://notebook.google/?location=unsupported']
    )
    assert_equal 'LIGHT_UNSUPPORTED_OBSERVED', classify(
      final: 'https://notebook.google.com/?icid=home_maincta',
      locations: ['https://notebook.google/?location=unsupported']
    )
    assert_equal 'LIGHT_UNSUPPORTED_OBSERVED', classify(
      final: 'https://notebooklm.google/?location=unsupported'
    )
  end

  def test_login_redirect_is_unknown_even_after_cta_get
    # In an unauthenticated external fetch of the observed CTA URL, Google
    # may redirect here. This is not a confirmed geo-compatible node.
    assert_equal 'LIGHT_LOGIN_REQUIRED_UNKNOWN', classify(
      final: 'https://accounts.google.com/ServiceLogin?continue=redacted',
      locations: ['https://accounts.google.com/ServiceLogin?continue=redacted']
    )
  end

  def test_marketing_200_does_not_pass
    assert_equal 'LIGHT_MARKETING_ONLY', classify(
      final: 'https://notebook.google/'
    )
  end

  def test_403_429_and_incomplete_request_cannot_be_access_gate_evidence
    [403, 429, 451].each do |code|
      assert_equal 'LIGHT_UNKNOWN_HTTP_ERROR', classify(
        final: 'https://notebook.google/?location=unsupported',
        code: code.to_s
      )
    end
    assert_equal 'LIGHT_UNKNOWN_INCOMPLETE_HTTP', classify(
      final: 'https://notebook.google/?location=unsupported', rc: 28
    )
  end

  def test_untrusted_hosts_and_malformed_location_do_not_false_block
    assert_equal 'LIGHT_UNKNOWN_UNREVIEWED_REDIRECT', classify(
      final: 'https://untrusted.example.invalid/',
      locations: ['https://notebook.google.evil.invalid/?location=unsupported']
    )
    assert_equal 'LIGHT_APP_HTTP_CANDIDATE_UNVERIFIED', classify(
      final: 'https://notebook.google.com/?icid=home_maincta',
      locations: ['https://evil.invalid/?location=unsupported']
    )
  end

  def test_url_encoded_location_flag_and_no_sensitive_output
    result = classify(
      final: 'https://notebook.google.com/',
      locations: ['https://notebook.google/?location=unsupp%6Frted&secret=SENSITIVE_FAKE_TOKEN']
    )
    assert_equal 'LIGHT_UNSUPPORTED_OBSERVED', result
    refute_includes result, 'SENSITIVE_FAKE_TOKEN'
  end

  def test_port_is_not_an_arbitrary_remote_proxy_or_controller_write
    assert_equal 'LIGHT_HOLD_INVALID_PORT', NotebookCtaLite.run_isolated(80)
    assert_equal 'LIGHT_HOLD_INVALID_PORT', NotebookCtaLite.run_isolated(0)
    source = File.read(File.expand_path('../scripts/ai_notebooklm_cta_light_probe.rb', __dir__))
    assert_includes source, "'--noproxy', ''"
    assert_includes source, "'--max-time', '12'"
    assert_includes source, "'--max-redirs', '4'"
    assert_includes source, "'--output', '/dev/null'"
    refute_includes source, "'-I'"
    refute_includes source, 'http://localhost'
    refute_includes source, 'cookies.txt'
  end
end
