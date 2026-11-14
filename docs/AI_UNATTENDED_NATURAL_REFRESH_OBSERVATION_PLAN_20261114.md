# 2026-11-14 23:59：自然订阅更新无人值守观察——生产部署前的安全设计（未安装）

## 当前已取得的证据与范围

- [23:59真实前台90秒实机回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_PASSIVE_FOREGROUND_90S_RECEIPT_20261114_2359.md)：固定Git `572e2e0e8e8869dfac836143b936913911d08ebf`的`--observe 90 30`成功启动、`BASELINE_SNAPSHOT=AVAILABLE ONLY_METADATA=YES`、最终`HOLD_NO_EVENT_BEFORE_DEADLINE`且正常回到shell，**只说明90秒内没更新**；`TRUSTED_REMOTE_COMMIT=NOT_VERIFIED MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED ALLOW_RECONCILE=NO ALLOW_SWITCH=NO`。
- [23:35实机Ruby四项能力](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_PASSIVE_RUNTIME_PREFLIGHT_PASS_RECEIPT_20261114_2335.md)：NOFOLLOW/flock/monotonic/trap PASS；前台试运行已经实机证实文件路径、当前唯一正式Mihomo和日志快照可取。
- 22:57单一显式启用订阅源、UCI `AUTO_UPDATE=ENABLED`、`CADENCE=DAILY`，**实际小时/分钟尚未由此次匿名实机输出证明**，不能猜测是凌晨4点或其他时刻。
- 22:29源文件与正式核心配置文件的58/58全连接参数定义匹配；22:20正式API叶节点58/58名字；21:09规则Provider20/20正数均已有真实PASS；不重做。
- 上游普通`Update Successful!`文本和文件metadata不是可信下载→校验→原子提交→核心实际加载的最终回执；观察器只能发现时间线候选，不得自动赋予节点资格。

## 方案A（优先设计）：有限窗口后台被动采集，设备无侵入

仅在用户**明确同意在iStoreOS临时保留一个只读进程**且通过单独的启动/停止/读取安全审查后才允许安装。

1. **时窗**：先通过已知安全的本地UCI计划项/cron来源证明实际更新时刻，若时间可证则以约更新时刻为中心选择有限观察窗；否则不凭猜测安排窄窗口。可选最多24小时一次性有界兜底，但必须评估路由器内存、进程/日志增长及手机断开后存活行为。
2. **低资源约束**：沿用已实机验证的单文件Ruby、只读本机UCI+源/核心metadata+有限增量日志；轮询不频于原程序允许的30秒，可选择120秒（若技术兼容，宁可降低采样精度）；单实例`File::NOFOLLOW`+0600`flock`；CPU和实际内存资源先有实机可观察上限，无异常自重启循环。
3. **自清理**：无持续cron/procd常驻守护、无无限自动重启；到时或首次判定`HOLD`/候选时间线后自行退出，TERM/HUP/INT受控停止；不得依赖手机浏览器一直开着。进程重启/日志轮转/文件暂缺/跨boot/身份不一致一律HOLD，不主动修生产配置。
4. **安全收据**：只在专用不公开的`/tmp`中写入**聚合枚举结果**，0600、有限字节、不会包含原日志行/机场URL/账号/代理地址或凭据；单次读取结果必须通过只读且匿名的脚本；明确保存截至时间和未验证字段。系统重启导致`/tmp`消失是`HOLD_EVIDENCE_LOST`，不是成功。
5. **幂等与停用**：安装前确认没有旧实例；停止必须验证预期PID、进程启动时钟和完整命令身份后才发TERM，不能用仅PID杀进程；卸载只移除本方案自有文件，日志/锁文件在持有者未退出前不得`unlink`，绝不碰OpenClash的配置、更新任务或原始日志。
6. **现实限制**：目前未实机验证在TTYD会话终止后`setsid`、`nohup`、`procd`或其他后台保活工具的实际可用性，**不能直接复制Ubuntu后台启动方式到OpenWrt**。需先离线代码/CI门禁再做一次无订阅变更的短时验证。真正上线后台属于新权限边界。
7. **硬性不会做**：不修改原订阅URL/更新时间/Worker/三端转换/非AI分流；不调用`OpenClash update`、重载`Mihomo`、进行代理节点PUT、触碰AI自动切组；`TRUSTED_REMOTE_COMMIT=NOT_VERIFIED`、`MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED`、`ALLOW_RECONCILE=NO`、`ALLOW_SWITCH=NO`必须保持。

## 方案B（备选）：不留后台进程

如果不授权临时后台采集，只能在用户能打开终端且恰好覆盖已核对更新窗口时运行**现有固定源码的有界前台命令**；若错过更新则结果只能`HOLD_NO_EVENT_BEFORE_DEADLINE`，不能把没有抓到事件解释成更新故障，也不得要求无限重复90秒烟测。此方案可靠性低，不能满足完全无人值守的目标。

## 需要另外审批的可信提交方案（本轮没有实施）

方案A捕获元数据及日志，**仍不足以证明**下载校验真正成功、持久化提交成功、Mihomo内存中完整认证和传输参数生效。如果未来一定要闭环，可再设计原OpenClash updater事务结束后的受保护收据/独立提交校验和核心实际运行代关联，先对照已知2026-11-14 07:51实机固定版本`ac6640de36be1cf7dc11ae73796a89078269542c`及是否发生升级，备份、兼容检测、原子恢复/撤销、生产故障回滚完成后**另行获得明确安装授权**，绝不假定已授权修改updater。

## 当前唯一下一步

工程端开发/离线合成测试**一次性有界无人值守启动器、私有收据读取器、身份核验的安全停止器**（或在架构审查中选择更简单的临时前台方法），并加入iStoreOS精简Ruby/P0/三端非AI完整CI；先别发可能长期运行的设备命令。CI确认后将**具体运行窗口、资源消耗、是否仅/tmp、回滚方法及对现网影响**集中展示给用户，由用户决定是否允许临时后台观察。**当前没有后台观察器安装或自动更新成功实机回执。**
