# 2026-11-15 OpenClash自然更新：受控无人值守观察器代码/CI交接（未部署）

## 用户目标与不可缩水验收

目标是将已通过前台90秒烟测的被动观察器用于**下一次自然订阅更新的有限无人值守窗口**，不要求用户手机TTYD长期打开；只读取原配置文件/正式Mihomo运行文件/进程启动代及有限增量原始日志，保留匿名观察回执。禁止主动刷新订阅、改OpenClash、Worker、三端、非AI分流，禁止自动选择/切换节点。即使观察到完整文件和进程变化，也只能产出候选时间线，不得伪称可信下载提交、内存密钥加载或ChatGPT/Gemini/NotebookLM业务资格。

- [23:59真实设备回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_PASSIVE_FOREGROUND_90S_RECEIPT_20261114_2359.md)：固定`572e2e0e`前台`--observe 90 30`，`BASELINE_SNAPSHOT=AVAILABLE ONLY_METADATA=YES`，正常退出`HOLD_NO_EVENT_BEFORE_DEADLINE`（这只表示90秒内没有更新，不是故障）；安全标记`ALLOW_RECONCILE=NO ALLOW_SWITCH=NO`。
- 23:35真实Ruby NOFOLLOW/flock/CLOCK_MONOTONIC/trap全部PASS；22:57真实UCI有1个显式启用的订阅节且`AUTO_UPDATE=ENABLED`、`CADENCE=DAILY`，**具体小时未取得**；22:29现行源/核心磁盘58/58全定义一致；22:20正式核心IPv4 API 58/58节点名字在运行态覆盖；21:09规则Provider20/20运行态正数。已完成项直接沿用，**不重跑**。
- 上游`config-subscribe.lua`的`auto_update_time`列表为设备本地0..23点整；但若实机缺少该UCI配置或非预约模式，必须`HOLD`，不得按UI默认值推断0:00。计划时间≠实际执行时间或更新成功。

## 本轮工程与测试结果（只确认Git/CI，不确认部署）

- 固定[**候选源码Git `e40a25797a61fcda99acadbbe1514af50e925941`**](https://github.com/Kimbersy/openclash/commit/e40a25797a61fcda99acadbbe1514af50e925941)；[完整GitHub CI **#43615879719**](https://github.com/Kimbersy/openclash/actions/runs/43615879719) `completed/success`，覆盖新控制器CI实际fork/setsid子进程及回执生命周期、进程停止身份校验、旧前台观察回归、单次UCI时间解析、精简iStoreOS静态准入、全部P0与三端非AI回归。
- 在同一个[被动观察器单文件Ruby](https://github.com/Kimbersy/openclash/blob/e40a25797a61fcda99acadbbe1514af50e925941/scripts/ai_refresh_passive_observer_candidate.rb)中增加离线候选控制模式：`--schedule`、`--status`、`--stop`、`--cleanup`、`--detach <duration> <interval>`；旧`--probe`和`--observe 90 30`入口保持不变。**`--detach`及后台部署仍被目标设备准入门禁阻断，不能给用户后台启动命令**：CI是在Ubuntu验证，不是iStoreOS已经证明fork/setsid或临时守护被批准。
- 候选`--detach`仅在明确时长、轮询与幂等条件成立时fork并setsid；专用`/tmp/ai_refresh_passive_control.lock` 0600 flock防并发、不在运行中unlink；`/tmp/ai_refresh_passive_session.state`仅记录私有PID、启动ticks、boot ID、观察预算；`/tmp/ai_refresh_passive_session.receipt`只允许读出白名单聚合枚举、不打印原日志/订阅名、URL、节点名或密码。父子进程的控制锁继承问题已修复，CI真实fork子进程/退场/匿名回执测试通过。
- `--status`保守区分`ABSENT/RUNNING/EXITED/HOLD_*`；`--stop`先检验boot+PID启动时钟+程序完整命令身份，之后只发送TERM并返回`TERM_SENT_NOT_CONFIRMED`，若身份不符拒绝，绝不`killall`或`kill -9`；`--cleanup`仅当确已退出且本方案私有文件通过NOFOLLOW/owner/0600验证时清理state/receipt，保留控制锁路径防互斥竞态。设备异常重启、状态文件伪装/损坏、进程身份未知均`HOLD`；需要另行审查手工恢复，不擅删生产文件。
- 新增[**单文件一次性准入探针**](https://github.com/Kimbersy/openclash/blob/e40a25797a61fcda99acadbbe1514af50e925941/scripts/ai_unattended_schedule_capability_readonly.rb)（0个`require`，仅本地`uci -q get`，不fork、不setsid、不写文件、不访问HTTP/Controller）：匿名输出设备实际`auto_update_time`小时`UCI_AUTO_UPDATE_HOUR`与Ruby `Process.respond_to?(:fork)/(:setsid)`方法是否**存在**。方法存在仍不代表真实fork/setsid可靠或批准运行后台。脚本经精简运行时静态门禁及CI核验。
- 审查上游Log`Update Successful!`与真实提交的信任边界没有变化：这些日志/文件metadata永远不能用来批准AI节点增量调和。任何自动业务资格与切组仍保持`TRUSTED_REMOTE_COMMIT=NOT_VERIFIED MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED ALLOW_RECONCILE=NO ALLOW_SWITCH=NO`。

## 当前唯一下一步（用户只需做一次安全只读检查，不是部署）

在iStoreOS TTYD仅执行下面**一条固定SHA**命令一次，回传截图中的`SCHEDULE_RESULT`、`UCI_AUTO_UPDATE_HOUR`、`RUBY_FORK_METHOD`、`RUBY_SETSID_METHOD`。下载只访问公共GitHub固定SHA源码；小程序本身只读本机4个UCI选项并询问Ruby方法是否存在，不读取/输出任何私人机场/节点信息，不创建长期进程：

```sh
( umask 077; f="$(mktemp /tmp/ai_schedcap_XXXXXX)" || exit 1; if curl -4 -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/e40a25797a61fcda99acadbbe1514af50e925941/scripts/ai_unattended_schedule_capability_readonly.rb"; then ruby "$f" || echo "SCHEDULE_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "SCHEDULE_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

**判断门禁**：若`DAILY_HOUR_DECLARED_ONLY`，只说明设备UCI明确声明该小时；`FORK/SETSID` 方法显示`PRESENT`也只表示Ruby方法存在。下一步要继续核对OpenWrt实际隔离、CPU/RSS、控制状态私有文件、TTY断开后生存行为和自动截止，再出**一次短时的后台候选测试**；如需真正跨日运行，须将拟定时窗、资源边界、撤销方式和风险集中交用户获得明确批准。若HOLD则根据分类修源码/检查，不改原机场订阅计划、IPv6/路由、Worker、三端，不重复旧实机证据。任何后台临时授权不等同于修改updater/长期cron或procd部署授权。

**现在的现场状态**：该后台代码仅存候选Git，GitHub CI通过；**家中没有安装后台观察器、cron/procd、自动切组或新的Listener**。现网服务和非AI流量不改，VPS继续HOLD。
