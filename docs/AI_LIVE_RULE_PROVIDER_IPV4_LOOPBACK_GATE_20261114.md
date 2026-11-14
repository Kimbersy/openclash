# 2026-11-14 20:54 后：IPv4 优先的正式 Controller 本地只读规则加载门禁

## 已确认设备与新增用户约束

- 用户于20:54运行固定 [`4fac6a4`](https://github.com/Kimbersy/openclash/commit/4fac6a4401ace4d1fa506a3a9a22247db73a6b4c) 的零HTTP socket诊断，真实 [原始匿名回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_SOCKET_OWNER_IPV6_RECEIPT_20261114_2054.md) 为：`BIND_CLASS=IPV4_WILDCARD`，`TCP4_PORT_LOOPBACK=0 TCP4_PORT_WILDCARD=0 TCP4_PORT_OTHER=0 TCP6_PORT_LISTEN=1 CORE_FD_PORT_MATCH=1 OWNER_EVIDENCE=IPV6_CORE_SOCKET_ONLY NETNS_SAME=YES SOCKET_DIAG_RESULT=ANONYMOUS_SOCKET_CLASSIFIED`。此时未执行任何HTTP/更新。
- **用户新约束**：家庭网络及AI服务使用IPv4优先，**不依赖IPv6出口**；不能因为内核存在IPv6监听就提出更改家用IPv6配置。IPv6 socket只是Controller内部监听实现，不能等同于AI业务出口IPv6。
- 此前20:33原只读GET在只支持IPv4归属的门禁处HOLD，**GET实际未发送**；19:22唯一大YAML浅层结构PASS、MRS文件头与预期不匹配HOLD；19:04格式19 YAML+1 MRS、17:20全部缓存字节复制PASS、17:06 Geo及15:46仅合成内核语法PASS、17:33缺unshare均保留；不再重复旧检查。

## 安全修订（只在候选代码，正式网络不改）

- [固定源码 Git `737fa71f040b7f34296b78ac9c89fecf480ea4da`](https://github.com/Kimbersy/openclash/blob/737fa71f040b7f34296b78ac9c89fecf480ea4da/scripts/ai_live_rule_provider_readonly.rb) 已修订：仍只对唯一正式Mihomo实际配置20份HTTP Rule Provider执行只读目录核对，仍核对`/proc/PID/exe`归属，新增`/proc/self/ns/net`与正式PID同网络命名空间校验，读取`/proc/PID/net/tcp`与`tcp6`目标端口的LISTEN socket inode及`/proc/PID/fd`归属。
- **IPv4唯一请求路径**：只有正式核心持有`127.0.0.1`或`0.0.0.0`的IPv4 socket；或真实设备这种**没有任何同端口IPv4监听且正式核心持有唯一IPv6 wildcard `::` socket**时，才允许继续。后一种情况仅把内核socket视为*可能支持IPv4-mapped连接*，**不证明它已接受IPv4**。其他IPv6如`::1`或远程地址、任何非正式进程占用IPv4端口、进程fd归属不清，一律HOLD，**不回退到任何IPv6 API地址**。
- `curl`强制`--ipv4`并且URL固定只访问`http://127.0.0.1:PORT/providers/rules`；仅`GET`，无PUT/刷新/healthcheck/下载规则，不代理、不重定向、不连接非HTTP协议；请求后再次核对监听socket归属，不一致立即HOLD。**如果该IPv6 socket为v6-only而无法接受IPv4，则返回`HOLD_IPV4_LOCAL_API_UNAVAILABLE`并停止，不改生产Controller配置、不转向IPv6请求。**
- Bearer token只能从本地现行配置读取，经curl标准输入传入，不写argv、GitHub、日志或终端；终端只输出`CONTROLLER_TRANSPORT=IPV4_LOOPBACK`、`SOCKET_OWNER_CLASS`、`LIVE_RULE_RESULT`、`API_EXPECTED_PRESENT/MISSING`、`API_RULECOUNT_POSITIVE/ZERO/UNKNOWN`以及MRS运行态类别等匿名字段。请求connect超时2秒、总时限7秒、最大响应1.5MiB；内核配置/真实规则/节点/地址或Provider名称不上传、不打印。
- **即使GET成功**，仅证明运行中的正式Mihomo通过其API报告已登记的Provider和部分ruleCount，不代表缓存内容/二进制MRS格式正确、所有规则有效、AI节点资格或自动切线已上线。原20:33安全门禁和此前真实MRS文件头不匹配仍为独立未完成证据。
- **回归与发布门禁**：[GitHub Actions #43597577395](https://github.com/Kimbersy/openclash/actions/runs/43597577395) `completed/success`，含IPv6 wildcard/IPv4 mapped候选、非loopback和他进程IPv4端口阻断、指定IPv4-only curl、旧API匿名规则计数、精简Ruby仅Psych依赖以及完整P0/三端与非AI回归。**这是CI合成结论，还未在家里实机GET**。仅更新候选分支，无生产配置/Worker/三端变更。

## 唯一下一步：一次固定SHA的正式内核IPv4 loopback只读GET

用户只需要在家里iStoreOS TTYD运行下面**唯一**固定源码命令一次；外层curl也强制`-4`使用IPv4下载公开固定Git单文件放在`/tmp`，内层脚本只尝试一次已通过监听归属检查的本机**IPv4** GET。不要安装软件或改IPv6：

```sh
( umask 077; f="$(mktemp /tmp/ai_rulelive_ipv4_XXXXXX)" || exit 1; if curl -4 -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/737fa71f040b7f34296b78ac9c89fecf480ea4da/scripts/ai_live_rule_provider_readonly.rb"; then ruby "$f" || echo "LIVE_RULE_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "LIVE_RULE_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

只回传`LIVE_RULE_RESULT`、`SOCKET_OWNER_CLASS`、`CONTROLLER_TRANSPORT`和所有`API_*`/ `MRS_RUNTIME_RULECOUNT`匿名行（或截图）。`HOLD`即停止，**不得重跑旧20:33脚本、20:54 socket探针、旧MRS/Geo/缓存检查，也不为通过而打开IPv6出口、修改Controller绑定或防火墙**。如果API显示20个全部登记，继续推进真实AI服务业务资格和安全灰度；如果HOLD，后续工程端仅针对新阻断码研究，不伪称系统故障。

P0最终交付为全部有效机场节点、ChatGPT/Gemini/NotebookLM独立资格、实测出口国家动态分组、订阅增量同步及稳态故障回退。此刻`BUSINESS=UNKNOWN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`，VPS仍暂缓。
