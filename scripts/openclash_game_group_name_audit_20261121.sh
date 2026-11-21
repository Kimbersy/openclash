#!/bin/sh
# One-shot read-only check of game node naming and country availability.
# Prints counts only, never names, subscriptions, servers or secrets.
set -eu
CFG='/etc/openclash/云.yaml'
[ -f "$CFG" ] && [ -r "$CFG" ] && [ ! -L "$CFG" ] || { echo 'HOLD: active YAML missing/unreadable/symlink'; exit 1; }
command -v ruby >/dev/null 2>&1 || { echo 'HOLD: ruby unavailable'; exit 1; }
ruby - "$CFG" <<'RUBY'
begin
  require 'psych'
  yaml = Psych.safe_load(File.read(ARGV[0]), permitted_classes: [], permitted_symbols: [], aliases: true)
rescue StandardError
  puts 'HOLD: YAML parsing failed; no content shown'
  exit 1
end
unless yaml.is_a?(Hash) && yaml['proxies'].is_a?(Array)
  puts 'HOLD: YAML does not contain a proxy list'
  exit 1
end

names = yaml['proxies'].select { |p| p.is_a?(Hash) && p['name'].is_a?(String) }.map { |p| p['name'] }
game_old = /(限速5M|游戏|[Gg]ame|[Gg]aming|联机|主机|电竞|PSN|PlayStation|Xbox|Nintendo|Switch)/
game_new = /([Mm]inecraft|[Bb]edrock|基岩)/
regions = {
  'HK' => /(香港|Hong[ -]?Kong|HKG|HK|🇭🇰|广港)/,
  'JP' => /(日本|Tokyo|Osaka|JPN|JP|🇯🇵|广日)/,
  'SG' => /(新加坡|Singapore|SGP|SG|🇸🇬|广新)/,
  'US' => /(美国|美國|USA|US|🇺🇸|广美)/,
  'TW' => /(台湾|台灣|Taiwan|TWN|TW|🇹🇼|广台)/,
  'KR' => /(韩国|韓國|Korea|KOR|KR|🇰🇷|广韩)/,
  'DE' => /(德国|德國|Germany|DEU|🇩🇪)/
}
puts "PROXY_TOTAL=#{names.size}"
puts "GAME_KEYWORD_OLD=#{names.count { |n| game_old =~ n }}"
puts "GAME_KEYWORD_NEW_ONLY=#{names.count { |n| !(game_old =~ n) && game_new =~ n }}"
regions.each { |country, rx| puts "REGION_#{country}=#{names.count { |n| rx =~ n }}" }
puts "REGION_ANY=#{names.count { |n| regions.values.any? { |rx| rx =~ n } }}"
groups = yaml['proxy-groups']
if groups.is_a?(Array)
  ['🎮 游戏节点-自动', '🎮 游戏节点', '🎮 游戏', '🎮 Xbox'].each do |group_name|
    item = groups.find { |g| g.is_a?(Hash) && g['name'] == group_name }
    key = case group_name
      when '🎮 游戏节点-自动' then 'GAME_AUTO'
      when '🎮 游戏节点' then 'GAME_SELECTOR'
      when '🎮 游戏' then 'GAME_TOP'
      else 'XBOX'
    end
    puts "#{key}_MEMBERS=#{item && item['proxies'].is_a?(Array) ? item['proxies'].length : 'UNKNOWN'}"
  end
end
puts 'AUDIT_RESULT=READ_ONLY_COUNTS_ONLY'
RUBY
