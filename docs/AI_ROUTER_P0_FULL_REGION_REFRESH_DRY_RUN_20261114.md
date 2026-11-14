# 路由器 P0：全订阅合格 AI 目录 → 动态地区组 → 增量更新离线闭环

**日期：2026-11-14；状态：候选源码和合成 CI PASS；未安装、无实际订阅成功事件、无真实 Mihomo 载入/业务回执。**

## 本轮目标与结果

承接[家庭 IT 默认分支不可缩水 P0 验收基线](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_AI_P0_ACCEPTANCE_CONTRACT.md)，本轮针对用户要求的 **全量合格节点、三项平台分开、真实出口国家自动分组、跟随原订阅增量变化**，做最小离线闭环，而不是继续增加独立测速/监控引擎。

候选新文件：[scripts/ai_full_region_refresh_dry_run.py](https://github.com/Kimbersy/openclash/blob/45714777868a23447f1fd8bf8e79e697d44333ee/scripts/ai_full_region_refresh_dry_run.py)，[tests/test_ai_full_region_refresh_dry_run.py](https://github.com/Kimbersy/openclash/blob/45714777868a23447f1fd8bf8e79e697d44333ee/tests/test_ai_full_region_refresh_dry_run.py)。

- [x] 复用已有`reconcile_subscription.validate_manifest`与`build_router_ai_p0_candidate.fingerprint`核对内嵌节点的**完整连接定义指纹**，严格拒绝同名冲突、目录缺节点或凭据暗变；未信任的额外API名字不进入合格池。
- [x] 复用`ai_refresh_transition_gate.decide_refresh`及`ai_dynamic_refresh_planner.updated_state`做离线增量：已确认`UPDATED`+真实快照变化时，根据全指纹新增排队、删除下架、同名换凭据撤销旧资格；未变身份保留**仍在有效期**且能被三项业务验证器认可的证据；只调整注释/排序不应清空全部结果。`NO_CHANGE`需快照一致，否则拒绝。
- [x] 复用`ai_service_stability_dry_run.qualified_pool`分别构建 ChatGPT、Gemini、NotebookLM 的全球池和三业务交集的全球池；按**双源已核实的出口国家**动态生出每一个有合格节点的国家组，没有固定TW/JP/US枚举，也没有3节点上限。
- [x] 生成新的`🛡️AI·全局稳态` / `🛡️AI·TW稳态` / `🛡️AI·US稳态`等共享三业务可用组，以及`🛡️AI·ChatGPT·全局`、`🛡️AI·Gemini·TW`等单平台独立目录。2条及以上使用Mihomo原生`fallback`；仅1条使用`select`，**不冒充有备用**。
- [x] 只把同时通过三平台的共享全球/地区组作为新**可选项追加**到旧`🤖 AI`人工select父组，**保留其全部旧成员与顺序、不自动选择**。单平台组虽被生成，但**不自动挂共享AI分流入口**，避免Google登录/NotebookLM跨域因不同出口混用而出错，服务级独立规则需要独立验收才能生效。
- [x] 不修改旧代理定义、现有规则、rule-provider、DNS、Controller secret、其他国家/非AI组或Android/Shadowrocket生成器；完全无配置写盘、网络探测、Controller PUT、服务重启、定时任务或守护进程。
- [x] 合成回归涵盖多国家全量生成、7条TW合格节点不能截断、只有ChatGPT合格不误抹单业务池、增加节点排队、删除节点地区消失、同名凭据变化资格撤销、格式变化继承证据、下载失败/未确认重载/非AI差异全部HOLD、未来Provider未完成证明时HOLD、组名冲突、额外未知API名字排除、匿名日志无敏感节点与凭据。

固定候选实现与CI：[Git `45714777868a23447f1fd8bf8e79e697d44333ee`](https://github.com/Kimbersy/openclash/commit/45714777868a23447f1fd8bf8e79e697d44333ee)；[GitHub Actions #43542978126](https://github.com/Kimbersy/openclash/actions/runs/43542978126) `completed/success`，包含新`Router P0 all AI service pools, dynamic real-egress countries and incremental refresh dry run`、旧路由器P0及跨端/非AI回归，均通过。

## 遗留 P0 门槛，不能虚报通过

1. **实际 OpenClash 更新事件 → 生成 → 受控配置载入**尚未接通。此程序接收经过调用者提供的`refresh_signals`和`coverage_verified`，这些**不是由程序实际采集或认证的**。官方`GET /proxies`只能证节点名字，不能证明新服务器密码/TLS凭据入内存；现有旧2026-11-13 58/58回执仍仅是目录证据。模拟把`full_runtime_reload_confirmed=true`不能充当实际设备回执。
2. **未来proxy-providers**：当前实机0 Provider、58内嵌为过往快照，新脚本在检测到非空Provider时会`HOLD_PROVIDER_SUPPORT_NOT_ATTESTED`，不会声称“全订阅已覆盖”。最终P0必须把已启用Provider的实际加载节点也覆盖、保留完整连接参数身份、去重冲突。
3. **真实AI业务资格采集**：本轮只验证已有BUSINESS_VERIFIED格式，未完成真实账号下ChatGPT流式、Gemini回答、NotebookLM工作区/来源导入/问答；本机新候选组没有已验证的真实合格节点。
4. **正式路由器接入与故障恢复**：尚未在真实Mihomo做`-t`、故障从主到备/无备用时的人工保留、健康恢复不抖动、配置回滚及非AI行为对照；动态地区组被移除时原本已选地区如何保留安全状态也需实机设计和验证。
5. **热备预算**：此候选会完整包含所有合格节点，Mihomo`fallback`的网络层低频探测和`lazy=true`不证明业务可用；正式规模若较大，应分层热备/冷备避免所有节点同步测造成路由器负载，而非丢弃其余合格节点。
6. **自动长期运行**：当前没有新常驻控制器、hook、cron、守护器、正式AI自动切换；不把CI通过写成生产部署成功。P1手机智能化可后续，现有三端转换不能被破坏。

## 唯一下一步

**只围绕路由器P0**：在候选分支识别OpenClash 0.47.151对当前活动配置可撤销、可验证的本地AI专用覆盖/后处理装配点，设计真实订阅更新完成后通过同源配置生成候选并以正式Mihomo校验、回读的最短受控流程；先完成*离线/隔离配置验证与回滚检查*，达到可安全灰度条件后才向用户集中提出是否安装。支持Provider的最终目标保留，但当前0 Provider不应为此强行改造现网。安卓/苹果P1不阻塞P0，不新造完整订阅系统，也不重扫58节点。
