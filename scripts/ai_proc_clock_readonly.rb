#!/usr/bin/env ruby
# frozen_string_literal: true
# Linux /proc starttime clock without getconf or optional Ruby stdlib.
# AT_CLKTCK is read from the current Ruby process's kernel auxiliary vector;
# the pointer-size unpack must match this same process, not a guessed platform.
# Never guesses 100 Hz, writes files, or prints any runtime identifiers.
module AiProcClockReadOnly
  module_function
  AT_NULL = 0
  AT_PAGESZ = 6
  AT_CLKTCK = 17

  def hz_from_auxv(raw)
    return nil unless raw.is_a?(String) && raw.bytesize.between?(32, 16_384)
    word_bytes = [0].pack('J').bytesize
    return nil unless raw.bytesize % (2 * word_bytes) == 0
    pairs = raw.unpack('J*').each_slice(2).to_a
    stop = pairs.index { |pair| pair[0] == AT_NULL }
    return nil unless stop && stop > 0 && pairs.drop(stop).all? { |pair| pair == [0, 0] }
    entries = pairs.take(stop)
    return nil if entries.any? { |type, _| type > 65_535 }
    clocks = entries.select { |type, _| type == AT_CLKTCK }.map(&:last)
    pages = entries.select { |type, _| type == AT_PAGESZ }.map(&:last)
    return nil unless clocks.length == 1 && pages.length == 1
    hz = clocks.first
    page_size = pages.first
    return nil unless hz.between?(10, 10_000)
    return nil unless page_size.between?(1_024, 65_536) && (page_size & (page_size - 1)).zero?
    hz
  rescue StandardError
    nil
  end

  def kernel_hz(path = '/proc/self/auxv')
    hz_from_auxv(File.binread(path, 16_384))
  rescue StandardError
    nil
  end

  def process_start_ticks(stat)
    return nil unless stat.is_a?(String) && stat.bytesize.between?(32, 32_768)
    end_of_comm = stat.rindex(') ')
    return nil unless end_of_comm && stat.include?('(') && end_of_comm > stat.index('(')
    fields = stat[(end_of_comm + 2)..-1].split
    return nil unless fields.length >= 20
    tick = Integer(fields[19], 10) # 22nd proc field; post-'comm' index 19
    tick if tick >= 0
  rescue StandardError
    nil
  end

  def boot_id(raw)
    value = raw.to_s.strip
    value if value.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
  end

  def core_start_time(pid, stat_path: nil, uptime_path: '/proc/uptime', auxv_path: '/proc/self/auxv')
    return nil unless pid.is_a?(Integer) && pid > 0
    hz = kernel_hz(auxv_path)
    return nil unless hz
    stat = File.binread(stat_path || "/proc/#{pid}/stat", 32_768)
    ticks = process_start_ticks(stat)
    return nil unless ticks
    uptime = Float(File.read(uptime_path).split.first)
    return nil unless uptime.positive? && ticks <= (uptime + 3) * hz
    now = Time.now
    when_started = Time.at(now.to_f - uptime + ticks.to_f / hz)
    return nil if when_started > now + 3
    when_started
  rescue StandardError
    nil
  end
end
