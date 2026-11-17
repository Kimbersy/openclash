# 2026-11-14 23:35 真实Ruby能力PASS后的90秒前台被动观察器试运行

## 既有真实证据（不重做）
- [23:35实机零额外Ruby依赖预检](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_PASSIVE_RUNTIME_PREFLIGHT_PASS_RECEIPT_20261114_2335.md)：NOFOLLOW/flock/CLOCK_MONOTONIC/TERM trap四项全PASS，`PASSIVE_OBSERVER_INSTALLED=NO`；本轮只是设备运行时能力，非长期观察器已实机验证。
- 22:57 订阅UCI显式启用1源/DAILY、非订阅配置选项40桶正确排除；22:29源与正式核心文件58/58完整定义一致；22:20正式API 58/58名字覆盖；21:09正式规则Provider20/20正数登记。**以上均有实机回执且不重复。**
- 已记录设备11月14日07:51安装updater的实际Git blob `ac6640de36be1cf7dc11ae73796a89078269542c`，与官方历史commit `813a60a21fba2ec34c3a42f7fdc3d71b47694d25`对应；未来安装真实hook前需要核对是否升级，当前不修改updater。

## 本轮工程变更与安全准入

- 完整源码固定[Git `572e2e0e8e8869dfac836143b936913911d08ebf`](https://github.com/Kimbersy/openclash/blob/572e2e0e8e8869dfac836143b936913911d08ebf/scripts/ai_refresh_passive_observer_candidate.rb)，[完整CI #43611675487](https://github.com/Kimbersy/openclash/actions/runs/43611675487) `completed/success`，包含原P0/三端/非AI回归、精简iStoreOS依赖及专项失效注入。
- 修复log增量误判：日志重写后字节数恰好相同亦`LOG_GAP`；不完整增量/替换或轮转保持HOLD；一次错误/缺口提示不会被后续`Update Successful!`覆盖；已拒绝日志符号链接路径。新增`--probe`一次快照模式；正式观察模式仍需显式`--observe duration interval`，默认未武装且绝不后台自启。INT/TERM/HUP均可停止；收到中断不继续采样。
- 已有23:35四项实机能力+11月14日多轮`uci`本机访问及核心PID配置读取的正式回执，满足本次**仅90秒前台试运行**所需的最小核心能力准入；新的CLI加入iStoreOS静态依赖合同，但**没有对24小时/后台/procd/cron安装进行准入**。
- 该候选仅读UCI已选源路径、唯一正式核心的PID/NetNS/starttime、两份配置磁盘元数据以及`/tmp/openclash.log`本地有限增量（单次≤128KiB）；不会打印任何实际日志行/代理名/订阅URL/地址/凭据，根本不请求HTTP/Controller、不执行任何更新、API组切换或配置写入。运行中可能创建专用`/tmp/ai_refresh_passive_observer.lock`，只用于flock，0600，不是OpenClash生产文件，脚本退出后释放（锁文件可保留，避免unlink竞争）。
- **任何观察结果都不能证明可信下载/提交和内存连接凭据**：`TRUSTED_REMOTE_COMMIT=NOT_VERIFIED`、`MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED`、`ALLOW_RECONCILE=NO ALLOW_SWITCH=NO`始终成立。即使日志成功、文件metadata及进程代全部变化，也最多`PASSIVE_POSTUPDATE_CHRONOLOGY_CANDIDATE_ONLY`；真正确认订阅更新需要独立保护型原始提交回执或其它可信证据。

## 当前唯一下一步：一次前台90秒干运行，非部署

在iStoreOS TTYD粘贴**下面固定SHA单条命令**，页面保持打开直至程序返回提示符，通常最长约90秒观察窗口（不包括程序下载、打开UCI等少量开销）；不要并发执行，遇到HOLD直接回传截图，不重试旧命令：

```sh
( umask 077; f="$(mktemp /tmp/ai_obs90_XXXXXX)" || exit 1; if curl -4 -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/572e2e0e8e8869dfac836143b936913911d08ebf/scripts/ai_refresh_passive_observer_candidate.rb"; then ruby "$f" --observe 90 30 || echo "PASSIVE_OBSERVER_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "PASSIVE_OBSERVER_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

**验收标准**：输出`PASSIVE_OBSERVER=START`、`BASELINE_SNAPSHOT=AVAILABLE ONLY_METADATA=YES`且结束时无私密正文、`ALLOW_SWITCH=NO`，即证明初始源/核心/日志定位和90秒有界试运行进入正常路径。如果没有恰巧更新，`HOLD_NO_EVENT_BEFORE_DEADLINE`是符合预期的诚实结果；不应解释成订阅失败。若`HOLD_INITIAL_SNAPSHOT_UNAVAILABLE`或`HOLD_SAMPLE_UNAVAILABLE`，依据固定类别修正路径/权限，**不能改变原生产配置凑PASS**；如日志缺口/错误则保持HOLD。运行完成截图即真实回执，届时再决定未来自然订阅更新的受控观察/保护型提交证据方案。

生产OpenClash、Worker、Android/iOS三端、非AI分流均未改，Listener NO，AUTO_SWITCH OFF，VPS HOLD。
