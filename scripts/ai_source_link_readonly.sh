ruby -rpsych <<'RUBY'
begin
  def ucivalue(key)
    IO.popen(['uci','-q','get',key],err:File::NULL){|io|io.read.to_s.strip}
  rescue StandardError
    ''
  end
  sec='openclash.@config_subscribe[0]'
  sections=IO.popen(['uci','-q','show','openclash'],err:File::NULL){|io|io.read}.scan(/^openclash\.([^.=]+)=config_subscribe\s*$/).flatten.uniq
  enabled=ucivalue(sec+'.enabled')
  raise 'changed_subscription_sections' unless sections.size==1 && enabled=='1'
  alias_name=ucivalue(sec+'.name')
  address=ucivalue(sec+'.address')
  selected=ucivalue('openclash.config.config_path')
  raise 'no_selected' if selected.empty?
  raw=File.expand_path(selected.start_with?('/') ? selected : File.join('/etc/openclash/config',selected))
  expected=File.expand_path(File.join('/etc/openclash/config',(alias_name.empty? ? 'config' : alias_name)+'.yaml'))
  match=(enabled=='1' && raw==expected)
  entry_count=address.split(/[\r\n|]+/).map{|x|x.strip}.reject{|x|x.empty?}.length
  puts "SOURCE=ONE_ENABLED ALIAS_MATCH=#{match ? 'YES' : 'NO'} LINK_ITEMS_HINT=#{entry_count}"
  raise 'outside' unless raw.start_with?('/etc/openclash/config/') && File.file?(raw) && File.size(raw).between?(1,20_000_000)
  raise 'symlink_source' unless File.realpath(raw).start_with?('/etc/openclash/config/')
  cfg=Psych.safe_load(File.binread(raw),aliases:false)
  raise 'bad_raw' unless cfg.is_a?(Hash) && cfg['proxies'].is_a?(Array)
  source_nodes=cfg['proxies']
  found=nil
  Dir['/proc/[0-9]*/cmdline'].each do |f|
    begin
      pid=f.split('/')[2]
      next unless File.readlink("/proc/#{pid}/exe").start_with?('/etc/openclash/core/')
      a=File.binread(f).split("\0")
      next if a.any?{|v|v.include?('/tmp/openclash-probe-')}
      opt=lambda{|k|i=a.index(k);i ? a[i+1] : a.find{|v|v.start_with?(k+'=')}&.split('=',2)&.last}
      cwd=File.readlink("/proc/#{pid}/cwd")
      dir=File.expand_path(opt.call('-d')||cwd,cwd)
      p=File.expand_path(opt.call('-f')||'config.yaml',dir)
      if File.file?(p) && File.size(p).between?(1,20_000_000)
        found=p;break
      end
    rescue StandardError
    end
  end
  raise 'no_runtime' unless found
  live=Psych.safe_load(File.binread(found),aliases:false)
  raise 'bad_runtime' unless live.is_a?(Hash) && live['proxies'].is_a?(Array)
  live_nodes=live['proxies']
  src_names=source_nodes.map{|n|n['name'] if n.is_a?(Hash)}.compact.sort
  live_names=live_nodes.map{|n|n['name'] if n.is_a?(Hash)}.compact.sort
  same_names=(src_names==live_names)
  same_defs=(source_nodes==live_nodes)
  age=Time.now-File.mtime(raw)
  bucket=age<0 ? 'FUTURE' : age<86400 ? 'LT24H' : age<604800 ? 'LT7D' : 'OLDER'
  puts "SOURCE_FILE=READABLE SOURCE_NODES=#{source_nodes.size} RUNTIME_NODES=#{live_nodes.size}"
  puts "RAW_RUNTIME_NAMES=#{same_names ? 'EQUAL' : 'DIFFERENT'} NODE_DEFINITIONS=#{same_defs ? 'EQUAL' : 'DIFFERENT'} SOURCE_FILE_AGE=#{bucket}"
  puts 'REMOTE_UPDATE_SUCCESS=NOT_VERIFIED'
rescue StandardError
  puts 'SOURCE_CHECK=UNAVAILABLE_NO_PRIVATE_OUTPUT'
end
RUBY
