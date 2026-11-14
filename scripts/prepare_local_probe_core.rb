# encoding: UTF-8
# Minimal fallback for OpenWrt ruby-core + psych. No tmpdir/json/digest/fileutils.
# Does not start Mihomo or modify any active service.
require 'psych'
begin
  if ENV['OC_TEST_MODE']=='1'
    src=File.expand_path(ARGV.fetch(0))
    root=File.expand_path(ARGV.fetch(1))
  else
    v=`uci -q get openclash.config.config_path 2>/dev/null`.strip
    raise 'no selected config' if v.empty?
    src=File.expand_path(v.start_with?('/') ? v : File.join('/etc/openclash/config',v))
    files=Dir['/etc/openclash/config/*.{yaml,yml}'].map { |x| File.expand_path(x) }
    raise 'not in config dir' unless files.include?(src)
    root='/tmp'
  end
  before=File.binread(src)
  raise 'invalid size' unless before.bytesize.between?(1,12_000_000)
  data=Psych.safe_load(before,aliases:false)
  nodes=data.fetch('proxies')
  raise 'invalid nodes' unless nodes.is_a?(Array) && nodes.all? { |n| n.is_a?(Hash) && n['name'].is_a?(String) && n['type'].is_a?(String) }
  raise 'duplicate names' unless nodes.map { |n| n['name'] }.uniq.size==nodes.size
  matches=nodes.select { |n| /香港|🇭🇰|\b(?:HK|HKG|Hong\s*Kong)\b/i.match?(n['name']) }
  selected=matches.first
  raise 'no eligible HK sample' unless selected && !selected['dialer-proxy'] &&
    !%w[direct reject reject-drop pass compatible].include?(selected['type'].downcase)
  raise 'subscription refreshed' unless File.binread(src)==before
  conf={'allow-lan'=>false,'mode'=>'rule','log-level'=>'silent',
    'port'=>0,'socks-port'=>0,'mixed-port'=>0,'redir-port'=>0,'tproxy-port'=>0,
    'external-controller'=>'','tun'=>{'enable'=>false},
    'profile'=>{'store-selected'=>false,'store-fake-ip'=>false},
    'proxies'=>[selected],
    'listeners'=>[{'name'=>'audit-only','type'=>'http','listen'=>'127.0.0.1',
                   'port'=>17881,'proxy'=>selected['name']}],
    'rules'=>['MATCH,REJECT']}
  dir=File.join(root,"openclash-probe-#{Time.now.to_i}-#{Process.pid}")
  created_dir=false
  Dir.mkdir(dir,0700)
  created_dir=true
  File.open(File.join(dir,'isolated.yaml'),File::WRONLY|File::CREAT|File::EXCL,0600) { |f| f.write(Psych.dump(conf)) }
  raise 'subscription refreshed' unless File.binread(src)==before
  puts "PREPARED_PRIVATE_DIR=#{dir}"
  puts "CURRENT_NODE_COUNT=#{nodes.size} HK_CANDIDATES=#{matches.size}"
  puts 'LISTEN=127.0.0.1:17881 STARTED=NO'
rescue StandardError
  if defined?(created_dir) && created_dir && dir && File.directory?(dir)
    private_file=File.join(dir,'isolated.yaml')
    File.unlink(private_file) if File.file?(private_file)
    Dir.rmdir(dir)
  end
  warn 'PRIVATE_PREP_FAILED'
end
