# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../scripts/ai_notebook_native_capability_test'

class AiNotebookNativeCapabilityTests < Minitest::Test
  M = AiNotebookNativeCapability
  def test_static_fixture_contains_only_synthetic_single_core_listener
    c=M.synthetic_yaml
    assert_includes c, 'type: http'
    assert_includes c, 'listen: 127.0.0.1'
    assert_includes c, 'port: 17881'
    assert_includes c, 'proxy: __AI_NOTEBOOK_PROBE_ONLY__'
    assert_includes c, 'SYNTHETIC_NO_NETWORK'
    assert_includes c, 'server: 192.0.2.1'
    assert_match(/proxies:\n\s+- REJECT/, c)
    refute_match(/(?:url:|proxy-providers:|rule-providers:|external-controller:|secret:|GEOIP)/, c)
  end
  def test_native_child_success_rejected_and_timeout_are_anonymous
    assert_equal 'NATIVE_LISTENER_SYNTAX_PASS',
      M.bounded_native_test(['/bin/sh','-c','exit 0'], seconds: 1.0)
    assert_equal 'HOLD_NATIVE_LISTENER_SYNTAX_REJECTED',
      M.bounded_native_test(['/bin/sh','-c','exit 3'], seconds: 1.0)
    start=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_equal 'HOLD_NATIVE_LISTENER_TEST_TIMEOUT',
      M.bounded_native_test(['/bin/sh','-c','exec sleep 5'], seconds: 0.2)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, :<, 2.0
    assert_equal 'HOLD_NATIVE_EXEC_UNAVAILABLE',
      M.bounded_native_test(['/path/does-not-exist'],seconds: 0.5)
  end
  def test_temporary_dir_is_private_and_cleanup_possible
    dir=M.temporary_dir
    refute_nil dir
    begin
      assert_equal 0700, File.stat(dir).mode & 0777
      assert_match(%r{\A/tmp/ai_nb_native_[a-f0-9]{16}\z}, dir)
    ensure
      Dir.rmdir(dir) if dir
    end
  end
  def test_device_script_is_dependency_free_and_does_not_use_real_config_for_test
    text=File.read(File.expand_path('../scripts/ai_notebook_native_capability_test.rb',__dir__))
    refute_match(/^\s*require(?:_relative)?\s/,text)
    assert_includes text, "File.binread('/dev/urandom', 8)"
    assert_includes text, "'-t', '-d', dir, '-f', file"
    assert_includes text, "File.delete("
    assert_includes text, "Dir.rmdir("
    refute_includes text, "openclash.sh"
    refute_includes text, "controller PUT"
    assert_includes text, "PRODUCTION_CONFIG=UNCHANGED"
  end
end
