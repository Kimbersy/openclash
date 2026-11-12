# 家庭 iStoreOS 单节点出口测试：安全的准备阶段（未启动核心）

更新：2026-11-12。**此流程只生成本地文件，不安装任何服务、不重启或更改现有 OpenClash，不影响原有 AI 组。**

## 已确认的事实与用途

- iStoreOS 已存在 Ruby/Psych、curl 和可执行的 Mihomo core；当前设备约 1100 MiB `MemAvailable`、`/tmp` 约 929 MB 可用（均为此前实机时点的状态，不能保证未来资源不变）。
- UCI 当前活动的机场订阅配置在路由器私有目录内。2026-11-12 17:52 的动态盘点快照显示 58 条**标称标签**：AU6、CA1、DE1、FR1、GB1、HK6、JP8、KR6、SG10、TW7、UNKNOWN7、US4。这不是各出口国家的真实观测结果，不能按此判断 NotebookLM/ChatGPT/Gemini 可用性。
- [`scripts/prepare_local_probe.rb`](../scripts/prepare_local_probe.rb) 是 Ruby/Psych 原生预处理工具；支持 HK、TW、JP、SG、US、KR、DE、GB、FR、CA、AU、NL、UNKNOWN、AMBIGUOUS 等标签选样，不固定实际节点数；默认选择指定标签的第 1 条，仅作为实验样本。
- 工具从 UCI 读取当前活动的**本机私有**完整 YAML，使用 `Psych.safe_load`，要求名字唯一、无额外 dialer-proxy 引用。只提取一个节点定义，写到权限 0700 的 `/tmp/openclash-probe-*/isolated.yaml`（0600）与源文件快照 `snapshot.json`（0600）。读取前后再检查原始订阅字节，遇刷新冲突则失败并删除未完成临时目录。**节点密码只存本机私有文件，不发送到 GitHub/聊天。**
- 配置中只有 1 个监听 `127.0.0.1:17881`、出站固定为所选单节点；`tun` 禁用，顶层端口为0、控制口空、LAN共享关闭，`MATCH,REJECT` 兜底。**只生成文件，未启动 Mihomo、未暴露任何局域网代理端口、未修改当前系统转发/DNS/规则/AI选择。**
- `--verify <PREPARED_PRIVATE_DIR>` 只检查生成批次时的 SHA256/字节数是否仍与当前活动订阅一致；机场更新后返回失败，不允许用旧的节点定义直接继续检测。

## 第一阶段（唯一当前实机步骤）：只准备，不启动

**从经过 CI 验证的固定 Git 提交获取脚本：**

```sh
umask 077
curl -fsSL --max-time 20 \
  'https://raw.githubusercontent.com/Kimbersy/openclash/c788706367d3122e1f6b6e94d8d1a5b3afbe8183/scripts/prepare_local_probe.rb' \
  -o /tmp/prepare-local-probe.rb &&
ruby /tmp/prepare-local-probe.rb HK 1
```

脚本回执仅有 `PREPARED_PRIVATE_DIR=/tmp/openclash-probe-...`、`CURRENT_NODE_COUNT`、`REGION`、`CANDIDATES`、`SAMPLE`、`LISTEN=127.0.0.1:17881 STARTED=NO LIVE_CONFIG_CHANGED=NO`；或 `PRIVATE_PROBE_CHECK_FAILED`。**不得 `cat` 生成的 `isolated.yaml` 或 `snapshot.json`，不要发送任何实际节点或机场信息。** 如果脚本无法从 GitHub 获取，不要换成不明来源的镜像脚本，应先停止并记录。

为什么先从 HK 选 1 条？只是一个**对照样本**，用户反馈部分香港线路 ChatGPT 可用、NotebookLM 可能不可用；它并非第一优先地区或最终规则，接下来还应分批验证 JP/SG/TW/UNKNOWN 等，按照实际出口 IP 和每项 AI 应用的真实功能决定用途。不能凭 HK 标签断言服务被限制。

## 后续阶段，不在此步执行

- 第二步：检查配置有效性与独立端口，核对**私有数据没有泄漏到日志**、系统剩余内存与订阅快照仍然最新；运行 `clash_meta -t -d <PRIVATE_DIR> -f <PRIVATE_DIR>/isolated.yaml` 时可能写入所选私有目录，**不是纯只读**；必须使用独立目录，严禁指向 OpenClash 正在使用的 `/etc/openclash` 数据目录。
- 第三步：评估资源占用与最短存活时间后才单独启动**受控的第二个 Mihomo**，通过仅本机 `curl --proxy http://127.0.0.1:17881` 获取两家 IP 回显，再核验国家一致性。必须确保关闭与清理，不把任何 IP 结果当成 AI 平台可用性证明。
- 第四步：按 ChatGPT/NotebookLM/Gemini 逐一实机验证、收集切换/断流数据和最新订阅快照，决定是否产生候选分流；现有 YouTube/Disney+ 和用户正在使用的 AI 选择保持不变。

## 证据与限制

- 基线/订阅动态机制：[方案](EGRESS_AUDIT_DESIGN.md)；[工程当前任务](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_CURRENT_WORK.md)。
- GitHub Actions [#43196657859](https://github.com/Kimbersy/openclash/actions/runs/43196657859) 已对**固定 Git 源 `c788706367d3122e1f6b6e94d8d1a5b3afbe8183`**运行 Ruby 语法与 46 项模拟/跨端测试 `success`，其中单节点脚本只使用合成假的节点凭据。
- 未有真实机场出口 IP、各 AI 服务资格、手机端业务或者 OpenClash 第二核心安装的验收回执。任何真实节点数量和服务资格都必须以未来实际采样为准。
- Mihomo 官方文档：[`listeners.proxy`](https://wiki.metacubex.one/en/config/inbound/listeners/) 可指定一个独立出站节点；[入站安全](https://wiki.metacubex.one/en/config/inbound/) 强调 HTTP/SOCKS 监听不能暴露到公网。

## 2026-11-12 19:18：路由器 GitHub 下载失败后的免下载回退

实机失败先后记录：`raw.githubusercontent.com` 报 `curl (35) SSL_ERROR_SYSCALL`；`api.github.com` 公共 Git blob 请求报 `curl (22) HTTP 403`。由于命令使用 `&&`，Ruby 脚本没运行；本机尚未生成单节点配置。不要推断是机场节点不能访问，更不能使用 `curl -k` 或调整现有 OpenClash。

**当前最快的安全回退**是从聊天中将下列短小的 Ruby here-doc 直接粘入 iStoreOS TTYD：它不需要联网、不安装软件、不执行先前下载失败的文件。它只在内存读取当前 UCI 配置，选择第一个标称 HK 样本，写入新建的私有 `/tmp/openclash-probe-*` 目录（0700）、两个文件（0600），监听声明固定 `127.0.0.1:17881`，并绑定原订阅字节快照。**没有运行新 Mihomo**，因此其监听声明不等于端口已开放。

```sh
umask 077
ruby -rpsych -rtmpdir -rdigest -rjson -rfileutils <<'RUBY'
begin
  files=Dir['/etc/openclash/config/*.{yaml,yml}'].map { |f| File.expand_path(f) }
  v=`uci -q get openclash.config.config_path 2>/dev/null`.strip
  raise 'no selected file' if v.empty?
  src=File.expand_path(v.start_with?('/') ? v : File.join('/etc/openclash/config',v))
  raise 'wrong file' unless files.include?(src)
  raw=File.binread(src)
  raise 'invalid size' unless raw.bytesize.between?(1,12_000_000)
  cfg=Psych.safe_load(raw,aliases:false)
  nodes=cfg.fetch('proxies')
  raise 'bad nodes' unless nodes.is_a?(Array) && nodes.all? { |n| n.is_a?(Hash) && n['name'].is_a?(String) && n['type'].is_a?(String) }
  raise 'duplicates' unless nodes.map { |n| n['name'] }.uniq.size==nodes.size
  hk=nodes.select { |n| /香港|🇭🇰|\b(?:HK|HKG|Hong\s*Kong)\b/i.match?(n['name']) }
  chosen=hk.first
  raise 'no HK sample' unless chosen
  raise 'dependent proxy' if chosen['dialer-proxy'] || %w[direct reject pass].include?(chosen['type'].downcase)
  raise 'subscription changed' unless File.binread(src)==raw
  conf={'allow-lan'=>false,'mode'=>'rule','log-level'=>'silent',
        'port'=>0,'socks-port'=>0,'mixed-port'=>0,'redir-port'=>0,'tproxy-port'=>0,
        'external-controller'=>'','tun'=>{'enable'=>false},
        'profile'=>{'store-selected'=>false,'store-fake-ip'=>false},
        'proxies'=>[chosen],
        'listeners'=>[{'name'=>'audit-only','type'=>'http','listen'=>'127.0.0.1',
                       'port'=>17881,'proxy'=>chosen['name']}], 'rules'=>['MATCH,REJECT']}
  dir=Dir.mktmpdir('openclash-probe-','/tmp')
  File.chmod(0700,dir)
  File.open(File.join(dir,'isolated.yaml'),'wx',0600) { |f| f.write(Psych.dump(conf)) }
  metadata={'sha256'=>Digest::SHA256.hexdigest(raw),'byte_count'=>raw.bytesize}
  File.open(File.join(dir,'snapshot.json'),'wx',0600) { |f| f.write(JSON.generate(metadata)) }
  raise 'subscription changed' unless File.binread(src)==raw
  puts "PREPARED_PRIVATE_DIR=#{dir}"
  puts "CURRENT_NODE_COUNT=#{nodes.size} HK_CANDIDATES=#{hk.size}"
  puts 'LISTEN=127.0.0.1:17881 STARTED=NO'
rescue StandardError
  FileUtils.remove_entry(dir) if defined?(dir) && dir && File.directory?(dir)
  warn 'PRIVATE_PREP_FAILED'
end
RUBY
```

上述短代码已在独立 Ruby 3.3 环境用合成私有 YAML 测试：单一 HK 节点输出包含 `STARTED=NO`，目录文件权限 0600、listener只监听127.0.0.1，生成文件中保留原私有节点内容；若没有 HK 节点仅返回 `PRIVATE_PREP_FAILED`。**这是本地模拟，不是家庭路由器实机通过**；路由器 Ruby/Psych 版本与 OpenClash YAML 的真实兼容性仍待用户回执。如果失败就停，不导出任何真实 YAML 内容或订阅信息。

完成后只报告匿名的 `PREPARED_PRIVATE_DIR` 与计数；**不可 cat/screenshot `isolated.yaml` 或 `snapshot.json`**，也不要重启/修改现有 OpenClash，下一步另做配置解析安全验证。
