#!/usr/bin/env ruby
# frozen_string_literal: true
# Private read-only helpers for UCI-selected subscription; no core is ever started.
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

# Isolated single-node probe PREPARATION only. Never starts a second core.
require "json"
require "digest"
require "socket"
require "tmpdir"
require "fileutils"

PROBE_PORT = 17881

def prepare_one(region, ordinal, source_override: nil, output_root: "/tmp")
  raise "unsupported region" unless LABELS.key?(region) || %w[UNKNOWN AMBIGUOUS].include?(region)
  raise "invalid rank" unless ordinal.is_a?(Integer) && ordinal.between?(1, 2000)
  source = source_override || active_config.first
  raise "invalid private config size" unless File.file?(source) && File.size(source).between?(1, 12_000_000)
  raw = File.binread(source)
  cfg = Psych.safe_load(raw, permitted_classes: [], permitted_symbols: [], aliases: false)
  raise "no proxies" unless cfg.is_a?(Hash) && cfg["proxies"].is_a?(Array)
  all = cfg["proxies"]
  raise "bad node list" if all.empty? || all.size > 2000
  raise "unexpected node structure" unless all.all? { |n| n.is_a?(Hash) && n["name"].is_a?(String) && !n["name"].empty? && n["type"].is_a?(String) }
  raise "duplicate node names" unless all.map { |n| n["name"] }.uniq.size == all.size
  candidates = all.select do |n|
    groups = LABELS.select { |_, pattern| pattern.match?(n["name"]) }.keys
    tag = groups.empty? ? "UNKNOWN" : (groups.length == 1 ? groups.first : "AMBIGUOUS")
    tag == region
  end
  raise "no such anonymous sample" unless ordinal <= candidates.size
  chosen = candidates[ordinal - 1]
  raise "builtin proxy type" if %w[direct reject reject-drop pass compatible].include?(chosen["type"].downcase)
  raise "dependent outbound requires independent validation" if chosen["dialer-proxy"].is_a?(String) && !chosen["dialer-proxy"].empty?
  # The inbound explicitly picks one real node. This does NOT use existing
  # OpenClash selected proxy groups or system TUN/transparent routing.
  config = {
    "allow-lan" => false, "mode" => "rule", "log-level" => "warning",
    "ipv6" => false, "port" => 0, "socks-port" => 0, "mixed-port" => 0,
    "redir-port" => 0, "tproxy-port" => 0, "external-controller" => "",
    "tun" => {"enable" => false},
    "profile" => {"store-selected" => false, "store-fake-ip" => false},
    "proxies" => [chosen],
    "listeners" => [{"name" => "private-egress-probe", "type" => "http",
                     "listen" => "127.0.0.1", "port" => PROBE_PORT,
                     "proxy" => chosen["name"]}],
    "rules" => ["MATCH,REJECT"]
  }
  raise "subscription refreshed" unless File.binread(source) == raw
  TCPServer.new("127.0.0.1", PROBE_PORT).close
  dir = Dir.mktmpdir("openclash-probe-", output_root)
  begin
    File.chmod(0o700, dir)
    File.open(File.join(dir, "isolated.yaml"), File::CREAT | File::EXCL | File::WRONLY, 0o600) do |f|
      f.write(Psych.dump(config))
    end
    meta = {"sha256" => Digest::SHA256.hexdigest(raw), "byte_count" => raw.bytesize,
            "node_count" => all.size, "region" => region, "ordinal" => ordinal}
    File.open(File.join(dir, "snapshot.json"), File::CREAT | File::EXCL | File::WRONLY, 0o600) do |f|
      f.write(JSON.generate(meta))
    end
    raise "subscription refreshed" unless File.binread(source) == raw
    puts "PREPARED_PRIVATE_DIR=#{dir}"
    puts "CURRENT_NODE_COUNT=#{all.size} REGION=#{region} CANDIDATES=#{candidates.size} SAMPLE=#{ordinal}"
    puts "LISTEN=127.0.0.1:#{PROBE_PORT} STARTED=NO LIVE_CONFIG_CHANGED=NO"
    dir
  rescue StandardError
    FileUtils.remove_entry(dir) if Dir.exist?(dir)
    raise
  end
end

def verify_prepared(dir, source_override: nil)
  meta = JSON.parse(File.read(File.join(dir,"snapshot.json")))
  now = File.binread(source_override || active_config.first)
  raise "subscription changed" unless meta["sha256"] == Digest::SHA256.hexdigest(now) &&
                                      meta["byte_count"] == now.bytesize
  puts "SUBSCRIPTION_SNAPSHOT=CURRENT"
end

if $PROGRAM_NAME == __FILE__
  begin
    if ARGV[0] == "--verify"
      raise "usage" unless ARGV.size == 2
      verify_prepared(ARGV.fetch(1))
    else
      raise "usage" unless (1..2).cover?(ARGV.size)
      prepare_one(ARGV.fetch(0).upcase, Integer(ARGV[1] || "1"))
    end
  rescue StandardError
    warn "PRIVATE_PROBE_CHECK_FAILED (no core started or live routing changed)"
    exit 2
  end
end
