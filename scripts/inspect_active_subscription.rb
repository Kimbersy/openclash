#!/usr/bin/env ruby
# frozen_string_literal: true
# Read-only, local-only node-label census for the CURRENT UCI-selected config.
# Outputs COUNTS ONLY. Never prints names, passwords, IPs, file names or URLs.
require "psych"

LABELS = {
  "HK" => /香港|🇭🇰|\b(?:HK|HKG|Hong\s*Kong)\b/i,
  "TW" => /台湾|台灣|臺灣|台北|臺北|🇹🇼|\b(?:TW|TWN|Taiwan|Taipei)\b/i,
  "JP" => /日本|东京|東京|🇯🇵|\b(?:JP|JPN|Japan|Tokyo)\b/i,
  "SG" => /新加坡|狮城|獅城|🇸🇬|\b(?:SG|SGP|Singapore)\b/i,
  "US" => /美国|美國|洛杉矶|洛杉磯|🇺🇸|\b(?:US|USA|United\s*States)\b/i,
  "KR" => /韩国|韓國|首尔|首爾|🇰🇷|\b(?:KR|KOR|Korea|Seoul)\b/i,
  "DE" => /德国|德國|🇩🇪|\b(?:DE|DEU|Germany)\b/i,
  "GB" => /英国|英國|🇬🇧|\b(?:GB|UK|United\s*Kingdom)\b/i,
  "FR" => /法国|法國|🇫🇷|\b(?:FR|FRA|France)\b/i,
  "CA" => /加拿大|🇨🇦|\b(?:CA|CAN|Canada)\b/i,
  "AU" => /澳大利亚|澳洲|澳大利亞|🇦🇺|\b(?:AU|AUS|Australia)\b/i,
  "NL" => /荷兰|荷蘭|🇳🇱|\b(?:NL|NLD|Netherlands)\b/i
}.freeze

def scalar_value(node)
  node.is_a?(Psych::Nodes::Scalar) ? node.value : nil
end

def active_config
  files = Dir["/etc/openclash/config/*.{yaml,yml}"].sort
  selected = IO.popen(["uci", "-q", "get", "openclash.config.config_path"], err: File::NULL, &:read).strip
  raise "no UCI active config" if selected.empty?
  absolute = File.expand_path(selected.start_with?("/") ? selected : File.join("/etc/openclash/config", selected))
  idx = files.index { |file| File.expand_path(file) == absolute }
  raise "UCI config not in expected directory" unless idx
  [absolute, idx+1]
end

def census(path)
  raise "config too large" if File.size(path) > 12_000_000
  root = Psych.parse_file(path)&.root
  raise "YAML root not mapping" unless root.is_a?(Psych::Nodes::Mapping)
  seq = root.children.each_slice(2).find { |key, _| scalar_value(key) == "proxies" }&.last
  raise "proxies is not a sequence" unless seq.is_a?(Psych::Nodes::Sequence)
  counter = Hash.new(0)
  seq.children.each do |proxy|
    fields = {}
    if proxy.is_a?(Psych::Nodes::Mapping)
      proxy.children.each_slice(2) do |k, v|
        fields[scalar_value(k)] = scalar_value(v) if scalar_value(k) == "name"
      end
    end
    name = fields["name"].to_s
    matches = LABELS.select { |_, pattern| pattern.match?(name) }.keys
    cc = matches.empty? ? "UNKNOWN" : matches.length == 1 ? matches.first : "AMBIGUOUS"
    counter[cc] += 1
  end
  [seq.children.length, counter.sort.to_h]
end

begin
  path, index = ARGV.empty? ? active_config : [File.expand_path(ARGV.fetch(0)), 0]
  count, totals = census(path)
  puts "SOURCE=#{index.zero? ? 'LOCAL_TEST_FILE' : "CONFIG_#{index}"}"
  puts "CURRENT_NODE_COUNT=#{count}"
  puts "LABEL_COUNTS=#{totals.map { |cc, n| "#{cc}:#{n}" }.join(',')}"
  puts "NOTE=Label-only census; actual exit IP and AI usability NOT checked"
rescue StandardError
  warn "PRIVATE_CONFIG_CENSUS_FAILED"
  exit 2
end
