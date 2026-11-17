# 2026-11-15 08:28 iStoreOS日更计划04时实机PASS后的fork/setsid单子进程准入（尚未实机运行）

## 已验收实机，不重复

[用户08:28 TTYD真实匿名回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_UNATTENDED_SCHEDULE_DEVICE_PASS_20261115_0828.md)：固定Git `e40a2579`返回`SCHEDULE_RESULT=DAILY_HOUR_DECLARED_ONLY UCI_AUTO_UPDATE_HOUR=04 RUBY_FORK_METHOD=PRESENT RUBY_SETSID_METHOD=PRESENT`，`UPDATE_EXECUTION=NOT_VERIFIED DEVICE_LOCAL_TIMEZONE=NOT_VERIFIED DETACHED_SESSION=NOT_STARTED`。**已经确认OpenClash UCI设置每天设备本地04:00的预约小时，但不等于当天真实更新成功或设备时区与手机一致；仅方法存在，实际fork/setsid仍未在iStoreOS运行。** 直接复用23:59前台90秒baseline PASS、23:35 Ruby NOFOLLOW/flock/clock/signal全部PASS、22:57 UCI一个显式启用日更源、22:29磁盘58/58完整字段、22:20内核API名字58/58、21:09规则Provider20/20，无任何重复检查。

## 本轮工程

- 固定[**Git `1b1a0c46ef00ca0685bd08d4e00b09dabacd86a1`**](https://github.com/Kimbersy/openclash/blob/1b1a0c46ef00ca0685bd08d4e00b09dabacd86a1/scripts/ai_unattended_fork_setsid_trial_readonly.rb)新建**一个单文件零require Ruby核心功能自检**，不读取订阅、OpenClash配置/日志或Mihomo进程、不请求任何HTTP、不访问Controller。仅当前Ruby进程fork一个临时子进程，在子进程内执行`Process.setsid`并校验会话ID与PID，一次性pipe回执后退出；父进程使用单调时钟与`waitpid2(WNOHANG)`最多约4秒等待，超时最多再做TERM短等并对**自己尚未回收的直接子进程**强制回收；从不发信号给OpenClash或其他PID。
- 输出仅匿名枚举`FORK_SESSION_TRIAL_RESULT=CHILD_SESSION_ISOLATION_PASS/HOLD_*`、`DIRECT_CHILD_REAPED=YES/NOT_CONFIRMED`、`BACKGROUND_SERVICE=NOT_INSTALLED CRON_PROCD=UNCHANGED`、`PRODUCTION_CONFIG=UNCHANGED ... AUTO_SWITCH=OFF`。方法不存在或运行失败就HOLD，绝不自动下载其它依赖或改系统设置。
- [完整CI #43658817161](https://github.com/Kimbersy/openclash/actions/runs/43658817161) `completed/success`，含单子进程短时自检真实CI Ubuntu执行并成功reap、旧后台控制器的状态文件/匿名回执/真实fork/stop测试、前台观察回归、iStoreOS最小Ruby依赖门禁、全P0/三端和非AI/原生Mihomo回归。**CI不等于用户iStoreOS实际执行PASS。**
- 现有候选后台`--detach`并**没有部署或安装**，仍需设备上实际安全后台启动/TTY断开/资源/安全停止与用户明确授权才能开启；这条单子进程自检只是其中一个准入条件。无人值守候选不会凭文件mtime/普通`Update Successful!`日志晋升为真实提交或内存连接凭据认证，`ALLOW_RECONCILE=NO ALLOW_SWITCH=NO`固定。

## 唯一下一步：一次固定SHA临时子进程自检（非后台部署）

在iStoreOS TTYD只执行下面**一条**命令一次，并回传`FORK_SESSION_TRIAL_RESULT`、`DIRECT_CHILD_REAPED`匿名结果截图。外层`curl -4`仅下载公开固定SHA代码，内层既无网络也无更新、原始配置读取或文件写入，理论操作时长数秒：

```sh
( umask 077; f="$(mktemp /tmp/ai_forktrial_XXXXXX)" || exit 1; if curl -4 -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/1b1a0c46ef00ca0685bd08d4e00b09dabacd86a1/scripts/ai_unattended_fork_setsid_trial_readonly.rb"; then ruby "$f" || echo "FORK_SESSION_TRIAL_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "FORK_SESSION_TRIAL_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

**PASS时的唯一解释**：设备Ruby可以短暂fork并setsid，子进程实际成功退出并回收。不能认为后台TTYD断线可存活、真实cron/定时观察已安装、内存占用验证、下一次04点自然更新已实际触发、远端源合并与Mihomo内存凭据已证。下一阶段先工程检查真实单实例有界后台生命周期/短时私有收据/停机语义，再集中给用户明确的影响、资源、时窗和撤销方案申请临时后台运行授权。出现`HOLD`就继续修兼容性/安全代码，**不改生产路由/自动更新时刻、不下载Ruby标准库或打开IPv6凑成功**。VPS仍HOLD。
