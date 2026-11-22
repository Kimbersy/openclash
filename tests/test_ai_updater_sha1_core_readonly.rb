# frozen_string_literal: true
require 'minitest/autorun'
require 'digest'
require 'tempfile'

source = File.read(File.expand_path('../scripts/ai_updater_sha1_core_readonly.sh', __dir__))
match = /ruby <<'RUBY'\n([\s\S]*?)\nRUBY(?:\n|\z)/.match(source)
raise 'inline Ruby missing' unless match
eval(match[1], TOPLEVEL_BINDING, 'ai_updater_sha1_core_readonly', 1)

class TestAiUpdaterSha1CoreReadOnly < Minitest::Test
  M = AiGitBlobSha1Core

  def test_sha1_standard_vectors_and_binary_content
    cases = ['', 'abc', 'a' * 55, 'a' * 56, 'a' * 64,
             'a' * 1000, "\x00\x01\xff\xfe".b,
             (0..255).map(&:chr).join.b * 63]
    cases.each do |value|
      assert_equal Digest::SHA1.hexdigest(value), M.sha1(value)
      expected = Digest::SHA1.hexdigest("blob #{value.bytesize}\0".b + value.b)
      assert_equal expected, M.git_blob_sha1(value)
    end
  end

  def test_long_exact_upstream_sized_fixture
    bytes = ((0..255).to_a.pack('C*') * 64).byteslice(0, 16_154)
    assert_equal 16_154, bytes.bytesize
    assert_equal Digest::SHA1.hexdigest("blob 16154\0".b + bytes),
                 M.git_blob_sha1(bytes)
  end

  def test_file_fingerprint_and_concurrent_modification_guard
    Tempfile.create('updater') do |f|
      data = ('#!/bin/sh' + "\n" + ('test-value' * 300)).b
      f.binmode
      f.write(data)
      f.flush
      assert_equal M.git_blob_sha1(data), M.installed_fingerprint(f.path)
      f.truncate(0)
      f.flush
      assert_equal 'SIZE_OUT_OF_RANGE', M.installed_fingerprint(f.path)
    end
    assert_equal 'NOT_READABLE', M.installed_fingerprint('/nonexistent-updater-probe')
  end

  def test_no_optional_dependencies_or_production_writes
    sh = File.read(File.expand_path('../scripts/ai_updater_sha1_core_readonly.sh', __dir__))
    refute_match(/(?:require ['"](?:digest|openssl|time)['"]|sha1sum|sha256sum|wc\s+-c|curl\s|wget\s)/, sh)
    assert_includes sh, 'PRODUCTION_WRITES=NONE'
    assert_includes sh, '/usr/share/openclash/openclash.sh'
    refute_match(/openclash\/config\/|\/proxies|\/configs/, sh)
  end
end
