# 2026-11-15 P0 最小真实业务试点：先验证现有 AI 出口，不扩展探针

## 目的和已确认工程事实

**目的**：从目前尚无任何真实三平台合格节点的状态，取得**一次实际使用、不变更现网**的 ChatGPT/Gemini/NotebookLM 功能观察，优先判断三服务在现有 AI 路由上是否能正常工作。没有业务证据就不构建生产自动切换池，也不以单个 HTTP/登录页当作 PASS。

已复用，不要重复：
- [P0不能缩水验收契约](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_AI_P0_ACCEPTANCE_CONTRACT.md)；
- [08:55实机fork/setsid PASS回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_FORK_SETSID_DEVICE_PASS_20261115_0855.md)；与 08:28 UCI 04时预约、23:59 前台观察、23:35 Ruby4项、22:57 一个启用订阅源、22:29 58/58完整连接定义、22:20 API名字58/58、21:09 20/20 rule providers。它们均**不是某节点的三平台实际合格证据**。
- `scripts/reconcile_subscription.py` 有完整节点定义指纹，`scripts/ai_service_stability_dry_run.py` 已要求逐平台实际账号工作流、区分正常/403/429/平台错误、真实出口双源/健康时效，`scripts/build_router_ai_p0_candidate.py` 已使用完整合格地区池，不存在永久三节点上限。[Git `6882e7e`](https://github.com/Kimbersy/openclash/commit/6882e7e9e6ceeb7c8ce6dc26134fa627eaae41db) / [CI #43541570607](https://github.com/Kimbersy/openclash/actions/runs/43541570607) 已确认 7 个同区合格节点全部保留。
- `scripts/audit_egress.py` 的双独立来源校验需要**隔离的同一节点 localhost CONNECT 代理**，普通浏览器分别打开 ipinfo/ipapi 可能走另一路由，**不得直接作为 AI 连接实际出口证明**。
- 之前的 01/09–11 出口和 NotebookLM 应用入口等均是历史网络线索，**不能成为 2026-11-15 的实时账号业务 PASS**。现有实时运行内存**完整认证参数**和一次真正订阅成功提交/载入均未验证，继续保持 HOLD。
- **暂不再扩展未部署的被动更新观察器**：其日志/文件时间线不能填补上述 P0 业务缺口。未经批准不装 cron/procd、第二核心、切换器、不改公共三端配置/Worker/订阅。

## 仅一次、零配置更改的业务基线观察（阶段 A）

**先观察当前正在用的 AI 路由，不改变任何策略组或节点。** 这一次只用于判断用户真实功能是否可用；当前节点的**完整身份、服务流量真实关联和双源IPv4出口未获证明**，所以这轮结果默认是`FUNCTIONAL_OBSERVATION_ROUTE_UNVERIFIED`，绝不向私有合格池写`BUSINESS_VERIFIED`。

在**真正通过家庭 iStoreOS/旁路由出网的 Windows 浏览器**（或已经确定经该路由出网的客户端）完成，建议避开手机4G/外部代理；若设备另开了独立VPN/Clash客户端/TUN、走外部网络、无法确认是否经家庭网关，则记录`PATH=UNKNOWN`，**不要把成功/失败归因于家中 OpenClash 的节点**。无需为了测试修改 Windows 网关、DNS、关掉日常保护或移动端代理。如果现有设备没有明确的家庭路由路径，先 HOLD 本轮业务观察。

使用现有真实账号，**不发送私密内容、不上传账号截图或包含姓名的NotebookLM来源**，只做：
1. **ChatGPT**：已登录 → 提交一条无敏感信息的简单提问 → 完整收到答案，若显示流式响应则确认能结束。对应 `signed_in/prompt_answered/stream_completed`。
2. **Gemini**：已登录 → 普通提问 → 完整收到答案。对应 `signed_in/prompt_answered`，记录 `unsupported/403/429` 等提示类别但不提交隐私日志。
3. **NotebookLM**：已登录 → 打开/建立一个空白笔记本 → 导入**非私密**公开文本或资料 → 提问并取得引用来源的回答 → 验证引用指向刚导入的内容。对应 `signed_in/workspace_opened/source_imported/question_answered/citation_checked`。仅能进入首页、登录页或成功导入但无法问答/引用，均不算业务通过。
4. **同一路由边界**：全过程不主动切换 `🤖 AI` 或共享地区组；这只保证**未有意换线**，不能独立证明三个服务真实连线使用同一叶节点。当前 `route_consistent=UNKNOWN`，直到独立关联正式Mihomo流量和完整身份。

**用户回报最少只需一段文字，不传账号内容**：
```text
设备路径：家庭旁路由确认 / 不确定
ChatGPT：完整问答PASS / FAIL(只写错误类型) / 未测
Gemini：完整问答PASS / FAIL(只写错误类型) / 未测
NotebookLM：导入+问答+引用PASS / FAIL(指出卡在登录/导入/问答/引用) / 未测
测试期间人工换线：否 / 是 / 不确定
```

## 阶段 A 之后，才决定哪些步骤有实际必要

- 若三者均功能成功：仅证明浏览器当时可用；**还不得发放节点业务合格身份**。之后才有必要设计一次隔离且可回滚的**同叶节点流量/出口关联**，使用现有`audit_egress.py`而不是重新开发全国节点扫描；完整指纹关联、两独立IPv4国别和近期健康/工作流再满足后允许入私有试点候选。
- 若只有部分服务成功：先按服务分开记`UNKNOWN/FAILED`，确认是平台限制、账号状态还是节点网络问题；评估按服务分组和Google共享登录/跨域路由一致性，**不因为 NotebookLM 失败就剔除 ChatGPT 合格候选**。
- 若三者均失败或路径UNKNOWN：不自动调换节点、不装探针，先判断上网设备是否真正经家中网关及是否平台/账号统一异常；无需重复节点58/58库存查询。
- **阶段 B 的唯一有价值技术验收**：在受控前提下把浏览器实时工作流关联到正式Mihomo同一完整身份、实际双源IPv4出口和不会影响非AI的隔离路由；需要临时修改AI路径或额外网络出口前，先向用户集中说明影响、回滚与验证目的，取得明确授权。不能凭被动文件mtime、普通成功日志、HTTP200或测试者口头“没改节点”认定完整身份已被证实。
- 阶段 C 才评估正式 AI-only 原生fallback/独立服务池和自动更新事件闭环。保持原`🤖 AI`人工选择/非AI/三端/Worker不变，AUTO_SWITCH OFF，VPS HOLD。

## 此阶段验收与当前唯一下一步

- **本轮已完成**：P0现实缺口核对、复用既有7条同区无上限代码、真实工作流检查项与隐私/路径/证据分级，**无新代码/CI/路由器操作**；未伪称已取得账号真实功能结果。
- **唯一下一步（用户条件满足时一次即可）**：在本来就由家庭 iStoreOS 出网的设备上，不换线地完成三平台真实业务基线，按上面的5行匿名文字反馈；若当前没有明确的家庭网关路径，先告诉我们`PATH=UNKNOWN`，工程再设计不扰动现网的路径识别。此项不需要任何TTYD命令，也不要求重新验收已通过的58条节点。
