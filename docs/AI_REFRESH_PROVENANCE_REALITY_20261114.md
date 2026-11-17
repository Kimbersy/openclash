# 2026-11-14 22:57：订阅UCI 1源日更真实PASS后，更新成功—实际内核生效证据的可行性审查

## 当前真正完成的验收（沿用，不重扫）

- [22:57订阅UCI实机回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_UCI_SUBSCRIPTION_PASS_RECEIPT_20261114_2257.md)：固定`a0b6cc7f`已实机返回`UCI_ENABLED_SOURCE_METADATA_CLASSIFIED`，1个显式启用、地址存在的`config_subscribe`，自动更新ENABLED / DAILY，孤立桶0，40个其他已声明类型UCI选项桶正确排除；22:47旧误报39不再有效。**日更只证明设置，不证明计划真正触发及成功**。
- 22:29正式Mihomo使用的配置文件与当前选中源文件58/58代理完整定义相同；22:20当前正式Controller IPv4 API节点名字58/58登记，内置`PASS-RULE`已识别；21:09正式规则Provider20/20登记且各自有正数规则数。**均非一次指定订阅更新事件的可信提交、完整内存凭据加载或业务平台资格证明**。
- 当前`ENABLED_SUBSCRIPTION_MERGE_PROVENANCE=NOT_VERIFIED`、`REMOTE_SUBSCRIPTION_REFRESH_SUCCESS=NOT_VERIFIED`、`MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED`、`AI_BUSINESS=UNKNOWN`；正式`LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`，VPS仍HOLD。

## 已核对上游源机制及不可跨越的证据边界

- 上游 [`vernesong/OpenClash` `openclash.sh`](https://github.com/vernesong/OpenClash/blob/master/luci-app-openclash/root/usr/share/openclash/openclash.sh)读取到的GitHub **Blob SHA `6c181265ca96c452660653d60ec552d58eccc12c`**（2026-11-14核对），在`config_su_check`中，检测到文件不同后执行`mv "$CFG_FILE" "$CONFIG_FILE" 2>/dev/null`，**下一句即输出`Config File...Update Successful!`，没有检查`mv`退出码**。旧日志中`No Change, Do Nothing!`同样只能代表当时执行到了对应分支。且仅在源是当前选中配置并且不带`norestart`时置`restart=1`，最后由`dec_job_counter_and_restart "$restart"`执行后续；此日志路径也不是完整的内核重载结果验收。
- 上游 [`config-subscribe.lua`](https://github.com/vernesong/OpenClash/blob/master/luci-app-openclash/luasrc/model/cbi/openclash/config-subscribe.lua)通过`auto_update`与`config_update_week_time=*`实现每天计划，UI旗标不是作业完成证据。
- 上游 [Issue #5239](https://github.com/vernesong/OpenClash/issues/5239)记录UI配置更新只显示已启动，不返回实际下载/写入最终成败；[Issue #5000](https://github.com/vernesong/OpenClash/issues/5000)、[Issue #5067](https://github.com/vernesong/OpenClash/issues/5067)存在“订阅文件更新、内核未自动生效”的设备报告，均只能作为风险例子，**不能据此断言这户机器出现相同故障**。
- **用户实机已安装的`/usr/share/openclash/openclash.sh`源码版本/日志行为尚未单独核验**，不能将当前上游master直接等同于家里版本。不能使用`Update Successful`日志文案、UI返回成功、`mtime`、当前`58/58`名字或两份磁盘YAML一致来伪造完整更新提交/载入证据。

## 下一阶段应交付的结构化证据，而不是重复读一遍配置

1. **前后有界快照**：候选本机观察器（先离线合成，不安装）在计划更新前建立当前可信源/运行配置的匿名版本摘要与正式核心 PID+启动时钟；在实际**原OpenClash**自动更新发生以后观测稳定源，确认该次执行没有错误或中途失败。未看到完整事件则标`UNKNOWN`，不猜测上次发生了什么。
2. **可信提交阶段**：必须能独立确认原更新命令真实返回、下载校验完成、源文件提交成功且已持久化；未修改原`openclash.sh`的普通日志不能构成这项证明。优先候选可停止的旁路被动观察，若确实需要在updater路径插入原子收据钩子，需先设计独立备份、回滚、版本升级兼容和明确授权；**未经用户许可不修改生产更新脚本**。
3. **真实内核生效阶段**：用同一批次ID关联正式Mihomo实际运行代及新配置版本，通过核心进程启动身份、唯一可信配置文件及其完整指纹快照、认证Controller实际目录/类型等**相互独立的证据**；若当前Mihomo API不能提供秘密认证字段，必须诚实标`MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED`而不是以名字匹配冒充“内存全连接参数已验证”。保留稳定样本/非AI变更零差异。
4. **判定与调用**：复用已经存在的离线`ai_refresh_event_gate.py`、`ai_refresh_transition_gate.py`，只能接入来源可信、批次一致且在有效期内的两阶段证据；即使判定`VERIFIED_SNAPSHOT_READY`，仅允许离线节点完整身份差异规划，不立即写配置或PUT切组。增加真实现场`1启用/58定义与名字都一致/无更新回执`的反向测试，确保仍是`HOLD_NO_REFRESH_PROOF`。
5. **避免无效循环**：本轮不再次要求用户运行22:57订阅源、22:29磁盘定义、22:20代理名字、21:09规则Provider以及更早缓存/Geo/socket探针；下一条设备命令应在完成可信观察器设计与完整CI后，直接为真实未来一次更新事件收集必要的新证据，而不是检查已知仍`NOT_VERIFIED`的旧数据。

## 当前唯一下一步（工程侧，用户暂无新操作）

对已经存在的离线门禁补“22:57实机组合事实不能当更新成功”的拒绝测试，并编写**可停止、单实例、低资源、只读不替换原OpenClash下载/更新逻辑**的观察器设计+合成测试与回滚方案；查看实际安装版本后才决定最小生产灰度。保持用户IPv4优先、不依赖IPv6，不改变任何三端公共订阅转换、Worker、DNS、OpenClash正式配置、AI或非AI策略组；P0全量有效节点和三AI真实业务/实测IPv4出口及稳态故障接替目标不缩水。
