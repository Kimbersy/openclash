# frozen_string_literal: true
require 'minitest/autorun'
require 'tempfile'
require_relative '../scripts/ai_proc_clock_readonly'

class TestAiProcClockReadOnly < Minitest::Test
  M = AiProcClockReadOnly
  def auxv(hz = 100, page = 4096)
    [6, page, 17, hz, 25, 200_000, 0, 0].pack('J*')
  end
  def stat(start = 98765)
    '123 (mihomo ) core) ' + (['S'] + Array.new(18, '0') + [start.to_s, '0']).join(' ')
  end
  def test_native_width_kernel_clock_from_auxv_without_external_commands
    assert_equal 100, M.hz_from_auxv(auxv)
    assert_equal 250, M.hz_from_auxv(auxv(250))
    if File.file?('/proc/self/auxv') && M.kernel_hz == 100
      assert_equal 100, M.kernel_hz
    end
  end
  def test_bad_or_truncated_auxv_fails_closed
    assert_nil M.hz_from_auxv(auxv[0..-3])
    assert_nil M.hz_from_auxv(auxv(0))
    assert_nil M.hz_from_auxv(auxv(100_000))
    assert_nil M.hz_from_auxv(auxv(100, 123))
    assert_nil M.hz_from_auxv([6, 4096, 0, 0].pack('J*'))
    assert_nil M.hz_from_auxv([6, 4096, 17, 100, 17, 100, 0, 0].pack('J*'))
    assert_nil M.hz_from_auxv([6, 4096, 17, 100, 0, 0, 99, 99].pack('J*'))
  end
  def test_proc_start_handles_parentheses_and_invalid_ticks
    assert_equal 98765, M.process_start_ticks(stat)
    assert_nil M.process_start_ticks(stat('not-a-number'))
    assert_nil M.process_start_ticks('123 (mihomo) S 0')
  end
  def test_core_start_conversion_and_missing_auxv_fail_closed
    Tempfile.create('auxv') do |a|
      Tempfile.create('stat') do |s|
        Tempfile.create('uptime') do |u|
          a.binmode; a.write(auxv); a.flush
          s.write(stat(1500)); s.flush
          u.write("30.00 0.00\n"); u.flush
          t = M.core_start_time(123, stat_path:s.path, uptime_path:u.path, auxv_path:a.path)
          assert_instance_of Time, t
          assert_in_delta Time.now.to_f - 15, t.to_f, 5
          a.rewind; a.truncate(0); a.write('invalid'); a.flush
          assert_nil M.core_start_time(123, stat_path:s.path, uptime_path:u.path, auxv_path:a.path)
        end
      end
    end
  end
  def test_malformed_and_missing_boot_identifiers
    assert_equal '12345678-1234-1234-1234-123456789abc', M.boot_id("12345678-1234-1234-1234-123456789abc\n")
    assert_nil M.boot_id('same-boot')
  end
end
