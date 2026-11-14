# 2026-11-14 20:33 Mihomo Controller归属HOLD后的零HTTP匿名诊断

## 不重跑的实机事实

- 用户在iStoreOS TTYD于20:33执行固定源码 [`f94c5f389a57fd5574af4624420e91dbd25a07ea`](https://github.com/Kimbersy/openclash/commit/f94c5f389a57fd5574af4624420e91dbd25a07ea)的只读Rule Provider API门禁，截图返回`RULE_PROVIDER_LIVE=START GET_ONLY=YES LIVE_RULE_RESULT=HOLD_CONTROLLER_OWNER_UNKNOWN`，`PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`。原回执：[家庭IT 20:33证据](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_LIVE_RULE_PROVIDER_OWNER_HOLD_20261114_2033.md)。**归属检查失败发生于GET发送之前；不能把本HOLD视为HTTP API失败、规则未加载或MRS格式损坏。**
- 之前19:22大YAML浅层结构PASS、MRS文件头HOLD，19:04缓存元数据20/20分类成功、18:18前18个YAML基本结构PASS、17:20全部20缓存逐字节副本核对/清理PASS、17:06 Geo、15:46纯合成Listener `-t` PASS、17:33 NetNS缺`unshare`均保持有效，不再重复。

## 完成的工程与审核范围

- 新增独立[零HTTP的 `scripts/ai_controller_socket_diagnostic_readonly.rb`](https://github.com/Kimbersy/openclash/blob/4fac6a4401ace4d1fa506a3a9a22247db73a6b4c/scripts/ai_controller_socket_diagnostic_readonly.rb)，Git固定`4fac6a4401ace4d1fa506a3a9a22247db73a6b4c`，只需已经证实存在的Ruby `psych`，不需要`timeout/open3/tempfile/uri/unshare`或外部系统诊断命令。
- 唯一正式核心及20个已有Provider布局门禁继续保留；从运行配置读取Controller本机IPv4 loopback/wildcard端口，在`/proc/PID/net/tcp`和`/proc/PID/net/tcp6`中**仅对内部端口做匹配，不回传端口或IP**；检查`/proc/PID/fd` socket inode能否对应，及设备与核心网络命名空间是否相同。
- 只输出匿名类别：`SOCKET_DIAG_RESULT`、`BIND_CLASS`、`PROC_TCP4_STATUS`、`PROC_TCP6_STATUS`、`CORE_FD_STATUS`、`NETNS_SAME`、相同端口的IPv4 loopback/wildcard/other及IPv6监听计数、`CORE_FD_PORT_MATCH`、`OWNER_EVIDENCE`。路径/原配置正文/真实端口/PID/Controller凭证/代理与Provider名/规则内容都不打印，也不上传。
- **不执行任何Controller HTTP GET/PUT**，不更新/修正端口、防火墙/内核/核心参数，不安装Listener，不调用第二核心，不启动AI切换；即使回执表明IPv6独占或FD不可见也不放宽上一个Token归属安全门禁。出现无证据即HOLD。
- [完整GitHub CI #43595872348](https://github.com/Kimbersy/openclash/actions/runs/43595872348) `completed/success`，合成IPv4/IPv6 socket行与inode归属分类、无HTTP/无敏感输出、精简iStoreOS Ruby依赖、全部P0候选、三端/非AI回归通过。**CI不是用户实机证据**，当前代码仅在Draft候选分支，生产配置未改。

## 唯一下一步：只读 `/proc` 单条TTYD命令

执行固定Git `4fac6a4401ace4d1fa506a3a9a22247db73a6b4c` 的单条命令，仅下载公开单文件脚本到`/tmp`临时位置，脚本自身无网络请求：

```sh
( umask 077; f="$(mktemp /tmp/ai_sockdiag_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/4fac6a4401ace4d1fa506a3a9a22247db73a6b4c/scripts/ai_controller_socket_diagnostic_readonly.rb"; then ruby "$f" || echo "SOCKET_DIAG_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "SOCKET_DIAG_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

只需返回本次程序打印的匿名状态（截图即可）。若`HOLD`，不重复上一条Rule Provider GET命令，更不得为求通过擅自关闭安全校验或改现网Controller配置。若能证明核心持有的socket监听形式，再基于原有只读GET方案做有证据的适配，且适配后需再通过Git固定提交+CI；未经验证绝不带Bearer请求未知Controller。VPS继续HOLD；AI真实业务`UNKNOWN`，Listener NO，AUTO_SWITCH OFF。
