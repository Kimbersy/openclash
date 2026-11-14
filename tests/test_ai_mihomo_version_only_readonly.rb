# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative '../scripts/ai_mihomo_version_only_readonly'

class TestActualCoreVersionOnly < Minitest::Test
  V = AiCoreVersionOnly
  def test_builtin_only_and_anonymous_output_contract
    path = File.expand_path('../scripts/ai_mihomo_version_only_readonly.rb', __dir__)
    src = File.read(path)
    refute_match(/^\s*require(?:_relative)?\s/, src)
    assert_includes src, 'exec /proc/#{pid}/exe -v 2>&1'
    assert_includes src, 'PRODUCTION_WRITES=NONE'
    assert_includes src, 'AUTO_SWITCH=OFF'
    refute_includes src, 'openclash.sh'
    assert_equal '1.19.34', V.extract_version("Mihomo Meta v1.19.34 linux amd64\n")
    assert_equal '1.19.34', V.extract_version("Mihomo Meta 1.19.34 (build)\n")
    assert_nil V.extract_version('unknown format')
  end

  def test_stderr_versus_stdout_and_unrecognized_without_raw_log_leak
    Dir.mktmpdir('version-check-') do |dir|
      stderr_cmd = "printf 'Mihomo Meta v1.19.34\\n' >&2"
      stdout_cmd = "printf 'Mihomo Meta v1.19.35\\n'"
      bad_cmd = "printf 'PRIVATE_TOKEN_NOT_TO_PRINT\\n' >&2"
      [
        [stderr_cmd, 'VERSION_IDENTIFIED', '1.19.34'],
        [stdout_cmd, 'VERSION_IDENTIFIED', '1.19.35'],
        [bad_cmd, 'HOLD_VERSION_FORMAT_UNRECOGNIZED', nil],
        [':', 'HOLD_VERSION_EMPTY_OUTPUT', nil],
      ].each do |cmd, expected_decision, expected_version|
        result = V.version_probe(['/bin/sh', '-c', cmd])
        assert_equal [expected_decision, expected_version], result
        refute_includes result.inspect, 'PRIVATE_TOKEN_NOT_TO_PRINT'
      end
    end
  end

  def test_hung_version_command_is_bounded_and_child_only
    start = Time.now.to_f
    result = V.version_probe(['/bin/sh','-c','exec sleep 3'], seconds: 0.15)
    assert_equal ['HOLD_VERSION_TIMEOUT', nil], result
    assert_operator Time.now.to_f - start, :<, 1.6
  end

  def test_unlaunchable_command_is_anonymous_hold
    result = V.version_probe(['/path/does-not-exist-version-check'], seconds: 0.4)
    assert_equal 'HOLD_VERSION_EXEC_UNAVAILABLE', result.first
    assert_nil result.last
    refute_includes result.inspect, '/path/does-not-exist-version-check'
  end
end
