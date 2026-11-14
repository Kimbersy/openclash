# 自然订阅更新 → Mihomo 启动因果关联（2026-11-14，候选代码已通过 CI，未部署）

## 本轮验收目标

- **可复用已完成实机事实**：2026-11-13 23:52 iStoreOS `CORE_TIME_STAGE=GETCONF_UNAVAILABLE`、`EXPECTED=58 PRESENT=58 EXTRA_LEAF=1`，其中58个预期名字全部在正式Mihomo认证API出现、额外1个未知且不准自动入池。已有用户回执仍有效，不重跑旧脚本。
- **解除精简系统时钟库限制但不降低证明门槛**：纯Ruby读取 Linux `/proc/self/auxv` 的`AT_CLKTCK`，本进程本机位宽`J`原生解码，并以`/proc/<pid>/stat`字段22和`/proc/uptime`计算启动时间；`auxv`不可读/不合法便`nil`，不安装系统命令、不猜100Hz。也能读取/验证boot UUID供今后防止跨重启错配。该逻辑已经替换候选`ai_refresh_activation_gate_readonly.rb`里的`getconf`依赖，旧决策的输出最多是`COLD_START_AFTER_UPDATE_CANDIDATE`，**仍不代表正式Mihomo内存凭据更新成功**。
- **独立因果门禁**：纯Python`ai_refresh_causal_sequence.assess_natural_refresh`合成检查：被信任的订阅真正下载校验与原子落盘事件→同一boot/run-id→内核辅助向量时钟→唯一正式核心**晚于提交**启动→来源与运行文件独立私有哈希、无并发写盘→该核心控制API鉴权且双次读取名字集合→仅输出`COLD_START_CHRONOLOGY_CANDIDATE_ONLY`。各输入仍需将来的真实受保护观察器，`source`等字符串和布尔值**不自带真实性**。
- **严格未授权**：即使所有合成信号全“通过”，新模块固定`runtime_identity_proven=false`、`allow_reconcile=false`、`allow_switch=false`、`writes=false`。真正正式运行的完整节点参数不可由常规`GET /proxies`名字/类型等列表反推出。独立真正运行身份/可信更新完成回执仍未取得，不得替现有`ai_refresh_event_gate.py`填入伪造的`authenticated_live_mihomo_snapshot`事件。
- **无生产变更**：此次没有安装观察钩子、没有触发远端订阅、没有重启Mihomo、没有新增cron/状态文件/PUT API、没有更改任何非AI或手机/Worker配置。VPS继续暂缓。

## 技术事实与来源

Linux`getauxval(AT_CLKTCK)`取自内核ELF auxiliary vector，代表进程计时的tick频率，可从`/proc/self/auxv`读本进程对应结构；来源：[Linux getauxval(3) manpage](https://man7.org/linux/man-pages/man3/getauxval.3.html)。此信息只保证候选代码可从内核获取**时钟标尺**，不证明用户 iStoreOS 的这个接口实际可读。程序不使用Ruby可选`time`或`getconf`，不可用就阻断。

Mihomo的`GET /proxies`能提供名称、代理类别、历史/状态和组成员等信息，不是完整加密代理服务器配置的运行快照接口；使用本机带鉴权GET不能当做`full_runtime_reload_confirmed`。[Mihomo API参考](https://wiki.metacubex.one/en/api/)与已验证的23:52设备回执均必须遵守此证据边界。

[OpenClash上游订阅配置UI](https://github.com/vernesong/OpenClash/blob/master/luci-app-openclash/luasrc/model/cbi/openclash/config-subscribe.lua)提供计划设置，但UI启动、更新日志`Update Successful!`、mtime和磁盘节点目录不构成独立的原子成功提交证明。实际用户安装版本的更新脚本未取逐字节指纹，不能直接用上游master假定本机脚本具备后置钩子。

## 合成场景回归

- AT_CLKTCK native-word解析/坏auxv/缺项/重复项/异常值/非法page-size、进程stat带括号的名字、起始tick转换与安全阻断。
- 订阅日志“成功”但没有真实commit观察器、UI点更新、下载失败、半写、错误快照摘要、运行盘后续修改；全部HOLD。
- 旧PID在更新前启动、无唯一核心、不同run-id、跨boot、老事件、异常clock/clock_hz、API双读不同、鉴权缺失、只有名字集合一致；全部HOLD。
- 合成完美的提交和冷启动也只返回`COLD_START_CHRONOLOGY_CANDIDATE_ONLY`，其中`runtime_identity_proven=false`且不得入池/切线；无凭据、节点名、私有摘要输出。
- 原既有升级门禁、三平台AI业务资格/防抖DRY_RUN、三端转换、非AI业务规则全部继续回归。

## 固定提交与 CI

- 候选分支`feature/egress-audit-20261111`固定提交 [8403f71ef4ed99da0bb21420b597016fe4a30939](https://github.com/Kimbersy/openclash/commit/8403f71ef4ed99da0bb21420b597016fe4a30939)。
- [GitHub Actions #43463373336](https://github.com/Kimbersy/openclash/actions/runs/43463373336) `completed/success`，其中新增`Kernel auxv clock and natural update chronology never fake runtime proof`、旧更新激活、三服务稳定性和三端回归均success。这只属于**源码和合成CI验收**，不是新实机时间源或真实订阅更新成功证明。

## 当前阻塞与唯一下一步

**最小可信观测环还缺两项真实来源**：
1. **真实的下载成功 + 校验 + 原子落盘后置回执**。需要先只读查用户已安装OpenClash更新脚本的版本与真实操作边界，才可能在隔离分支设计带run-id/boot-id/规范源摘要的最小受保护观察钩子；任何钩子首次接入/重载都必须另有用户认可的安装与回滚方案，不能修改现网订阅流程。
2. **Mihomo完整运行身份的独立证明**。当前官方控制API常规`GET /proxies`不足以核对服务器/认证/TLS连接指纹。可以进一步审计上游是否提供安全的专用运行身份手段，或者将受保护的冷启动+配置一致+实际业务验证明确视为**低一级运维证据**；不能悄悄更改原有“完整身份验收”标准。不能用原始日志字符串伪造后置回执。

**唯一下一步：继续代码侧审计可信观察钩子的安全落点和Mihomo运行身份可观测能力，形成可安装、可撤销、完全脱敏的候选观察方案及离线测试。在能拿到真实可信二元证据前，自动资格继承、自动选择、三端发布均保持锁定。当前不要求用户执行TTYD命令。**
