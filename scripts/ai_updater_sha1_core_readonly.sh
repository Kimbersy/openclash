#!/bin/sh
# One-shot, read-only installed OpenClash updater fingerprint.
# Pure Ruby core: no shell hash helpers, extra libraries, download or config changes.
umask 077
ruby <<'RUBY'
module AiGitBlobSha1Core
  MASK = 0xffffffff
  module_function

  def rol(value, bits)
    ((value << bits) | (value >> (32 - bits))) & MASK
  end

  def sha1(message)
    return nil unless message.is_a?(String)
    b = message.b.dup
    length = b.bytesize * 8
    b << "\x80".b
    b << ("\x00".b * ((56 - b.bytesize % 64) % 64))
    b << [length >> 32, length & MASK].pack('N2')
    hash = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0]
    b.bytes.each_slice(64) do |slice|
      words = slice.pack('C*').unpack('N16')
      (16...80).each do |i|
        words[i] = rol(words[i-3] ^ words[i-8] ^ words[i-14] ^ words[i-16], 1)
      end
      a, c, d, e, f = hash
      80.times do |i|
        case i
        when 0..19
          function = (c & d) | ((~c) & e)
          constant = 0x5a827999
        when 20..39
          function = c ^ d ^ e
          constant = 0x6ed9eba1
        when 40..59
          function = (c & d) | (c & e) | (d & e)
          constant = 0x8f1bbcdc
        else
          function = c ^ d ^ e
          constant = 0xca62c1d6
        end
        step = (rol(a, 5) + function + f + constant + words[i]) & MASK
        f = e
        e = d
        d = rol(c, 30)
        c = a
        a = step
      end
      hash = hash.each_with_index.map { |x, i| (x + [a, c, d, e, f][i]) & MASK }
    end
    hash.pack('N5').unpack('H*').first
  end

  def git_blob_sha1(content)
    return nil unless content.is_a?(String)
    sha1(("blob #{content.bytesize}\0".b + content.b))
  end

  def installed_fingerprint(path)
    return 'NOT_READABLE' unless File.file?(path) && File.readable?(path)
    before = File.stat(path)
    return 'SIZE_OUT_OF_RANGE' unless before.size.between?(200, 500_000)
    data = File.binread(path, 500_001)
    after = File.stat(path)
    stable = [before.dev, before.ino, before.size, before.mtime, before.ctime] ==
             [after.dev, after.ino, after.size, after.mtime, after.ctime]
    return 'FILE_CHANGED_DURING_READ' unless stable && data.bytesize == before.size
    git_blob_sha1(data)
  rescue StandardError
    'UNAVAILABLE'
  end
end

if __FILE__ == $PROGRAM_NAME
  puts 'UPDATER_FINGERPRINT=START READ_ONLY=YES'
  value = AiGitBlobSha1Core.installed_fingerprint('/usr/share/openclash/openclash.sh')
  if value == '6c181265ca96c452660653d60ec552d58eccc12c'
    puts "INSTALLED_UPDATER=PINNED_OCT2026 GIT_BLOB_SHA=#{value}"
  elsif value.match?(/\A[0-9a-f]{40}\z/)
    puts "INSTALLED_UPDATER=DIFFERENT_VERSION GIT_BLOB_SHA=#{value}"
  else
    puts "INSTALLED_UPDATER=#{value}"
  end
  puts 'UPDATER_FINGERPRINT=FINISHED PRODUCTION_WRITES=NONE'
end
RUBY
