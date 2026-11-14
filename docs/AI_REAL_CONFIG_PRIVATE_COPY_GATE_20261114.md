# 路由器P0：真实配置私有副本的最小 AI-only 监听器合成与安全准入（2026-11-14）

> **本轮代码与CI离线验证完成；真实用户路由器**尚未运行此私有副本测试。此前15:46家中真实内核对**无机密合成配置**的原生`-t`已通过且临时目录清理成功。不要重做15:02唯一核心/17881监听/运行配置结构或15:22版本格式/15:46合成`-t`。本轮验证的是**保留实际完整源配置语义后追加Listener**的新阶段，不是反复测同一功能。

## 关键安全问题和处理

实际OpenClash配置可能包含凭据、Provider、远程规则集、GeoIP/GeoSite和其他外部资源。与15:46的纯合成YAML不同，实际配置执行`mihomo -t -d /tmp/...`可能需要或触发对本地数据集、远程文件的处理。官方[Rule-Providers文档](https://wiki.metacubex.one/en/config/rule-providers/)有HTTP下载及受`HomeDir`约束的文件路径机制；不能把`-t`笼统宣传为对任意配置保证零网络副作用。

因此实现**先解析并匿名审查，再决定是否允许私有副本原生测试**，且默认对未知来源结构fail-closed：

- **实际源仅保留在用户路由器**：Ruby单文件脚本读取唯一实际运行核心所用YAML，不向GitHub、聊天或日志输出原YAML、节点名、服务器、订阅URL、密码、Secret或测试出错的原始文本。脚本依赖仅`psych`，已由用户15:02真实设备证实可加载；不要求`timeout`、`open3`、`uri`、`tempfile`或Python。
- **明确风险不运行真实内核测试**：源中有`proxy-providers`、`rule-providers`、未知provider形状、group`use`/自动导入、`GEOSITE`/`GEOIP`/`RULE-SET`（含嵌套）、`geodata-mode`/`geo-auto-update`/`geox-url`、脚本/外部资源、名称/端口冲突、原AI组类型改变，返回匿名`HOLD_*`且**不建立私有副本/不执行`-t`**。不能因为HOLD就偷偷剔除原有规则或远程资源来制造PASS；未来Provider仍需覆盖，当前只表示独立测试门禁。
- **仅无以上已知外部依赖时**：原配置在内存深拷贝，只在尾部新增一个`__AI_NOTEBOOK_PROBE_ONLY__`、`REJECT`首项人工select并包含**所有原内嵌叶**，追加`127.0.0.1:17881`仅本机HTTP listener。逐项检查原`proxy-groups`、`listeners`、`proxies`、`rules`、DNS、订阅节点凭据未变，再用`Psych.dump`并回读语义相等；只写0700随机`/tmp`目录、0600私有副本，使用**当前已装Mihomo二进制**对这个副本运行一次最多12秒的`-t`；输出匿名PASS/HOLD并删除本次私有副本及其缓存，不跟随symlink、不使用真实`-d`、不重载现网。
- **没有真实配置的测试结果前，不承诺一定会PASS**。与原有实际运行完整字段的兼容性、远程文件解析、旧式Provider、Source身份、内部持久缓存仍未验；如果检测HOLD，需要专门设计具受保护数据的本地资源副本，而不是移除本轮P0所有Provider/全节点要求。
- **先验语法而非安装**：`mihomo -t`成功也只说明完整私有候选能被解析，不代表部署或运行中的检测group实际上在REJECT。正式新增listener仍需用户**另行明确许可**、备份、可回滚hook与真实Controller只读回执；不能改变`🤖 AI`及国内/Disney/媒体/GitHub/Telegram/Worker/现有三端自动订阅。

## 固定工程验收（源码/CI）

[固定候选Git `43e9ae2bd0b01d3dfb65e2328803073986290930`](https://github.com/Kimbersy/openclash/commit/43e9ae2bd0b01d3dfb65e2328803073986290930)。
[GitHub Actions #43575448709](https://github.com/Kimbersy/openclash/actions/runs/43575448709) `completed/success`：
- [`scripts/ai_real_config_private_copy_native_gate.rb`](https://github.com/Kimbersy/openclash/blob/43e9ae2bd0b01d3dfb65e2328803073986290930/scripts/ai_real_config_private_copy_native_gate.rb) 是独立路由器运行时Ruby单文件，实机尚未运行；
- [合成单元回归](https://github.com/Kimbersy/openclash/blob/43e9ae2bd0b01d3dfb65e2328803073986290930/tests/test_ai_real_config_private_copy_native_gate.rb)包含原AI/非AI/凭据/规则不变、70条以上叶完整保留、已有listener不变、provider/geo及畸形资源HOLD、端口/组名冲突拒绝、私有目录0600/0700及不跟随symlink、进程退出有界，以及iStoreOS精简Ruby依赖硬性白名单；
- [原生增量配置合成fixture](https://github.com/Kimbersy/openclash/blob/43e9ae2bd0b01d3dfb65e2328803073986290930/tests/make_ai_real_private_copy_mihomo_fixture.rb)通过**官方校验SHA256的Mihomo v1.19.34二进制`-t`**，这次比先前15:46的最小合成YAML多了保留原AI/Disney分组和规则的增量副本测试；
- 既有全启用节点发现/地区/三服务资格、历史订阅增量状态、三端冻结及非AI零差异回归仍通过。

## 唯一下一步

在家中路由器**一次性尝试真实配置的匿名风险门禁**：输入只有程序固定版本，不输入/上传真实订阅URL、节点名和密码。**执行前须知：只有通过外部依赖和结构检查后，程序才会在路由器本机0700临时目录短暂保存一份含真实节点凭据的0600副本，并让当前Mihomo对它运行最多12秒的原生配置校验；测试结束尽力清除。公网仓库或聊天不接收该副本。**

固定提交的单条TTYD执行命令（此命令**尚未在用户设备运行过**，不等于真实审计已通过）：

```sh
( umask 077; f="$(mktemp /tmp/ai_private_gate_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/43e9ae2bd0b01d3dfb65e2328803073986290930/scripts/ai_real_config_private_copy_native_gate.rb"; then ruby "$f" || echo "PRIVATE_COPY_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "PRIVATE_COPY_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

只回传`PRIVATE_COPY_RESULT`、`TEMP_CLEANUP`等匿名枚举；若返回`HOLD_*`，**不要求立刻再执行其他诊断命令**，先根据具体HOLD类别决定如何处理依赖。若触发任何`HOLD_*`，记录该项真实配置依赖，**不执行危险`-t`**；如果返回`PRIVATE_COPY_SYNTAX_PASS`与`TEMP_CLEANUP=YES`，则推进备份/正式OpenClash成功更新集成点和受控灰度安装审批，不重新分析版本号、旧端口或合成listener。该检查本身会短暂在本机/tmp创建含完整节点凭据的0600配置副本并在12秒内执行原生`-t`，若通过风险门禁；**该行为还未在设备实际验证**，本轮不提供默认自动部署和不写OpenClash正式配置。用户允许真实副本本地检查时，再按固定Git提交给出唯一命令，避免手机误操作；若用户暂时不方便，保持唯一下一步，不增加新的准备性扫描。

**仍未完成**：实际NotebookLM`unsupported`/支持节点CTA正负轻量HTTP校准、NotebookLM来源导入/问答/引用与同出口、ChatGPT/Gemini同出口及AI合格池、随原订阅更新全量动态国家分组、稳态主备/故障恢复。所有P0用户长期要求继续有效，安卓苹果智能化仅P1。当前`LISTENER_INSTALLED=NO AUTO_SWITCH=OFF BUSINESS=UNKNOWN PRODUCTION_CONFIG=UNCHANGED`。
