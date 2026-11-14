# NotebookLM低能耗预筛：无需浏览器的固定试用入口 HTTPS GET（2026-11-14）

> **状态：外部公开来源确认试用按钮的目标URL + 轻量纯Ruby/curl实现与CI合成回归PASS；未通过用户家中节点正负样本校准、未安装或接入自动订阅调度，不可据此授予业务合格。** 用户强调最小能耗、尽量只使用现有Ping/订阅URL，并同意若不够则按已有方案继续。

> **2026-11-14 11:12 用户补充真实经验（优先适用）**：NotebookLM不支持的当前代理节点**即使能正常访问Google、YouTube**，点击`notebook.google`上的“试用 Gemini Notebook”**也直接进入`location=unsupported`，不会先进入Google登录流程**；在已观察的支持节点上，点击后先走`notebook.google.com/?icid=...`、必要时Google登录、随后进入正常工作台。因此`location=unsupported`是该次CTA测试明确受限信号；**登录链路或icid都是值得后续验证的积极分支，但都不等于已完成Notebook业务**。此行为来自用户真实Chrome观察，**还不是路由器自动GET在两条完整指纹节点上的对照回执**；不能把一次无登录态GET的积极分支单独升格为`BUSINESS_VERIFIED`。本轮已将Ruby工具的原`LIGHT_LOGIN_REQUIRED_UNKNOWN`调整为`LIGHT_LOGIN_PATH_CANDIDATE_UNVERIFIED`，保留`unsupported`重定向优先级，防止普通Google/YouTube可访问假阳性，源码及测试固定[Git `78bf69c`](https://github.com/Kimbersy/openclash/commit/78bf69c01af5aeb41c62f377b27fe2db13f3b801)。

## 一、用户目标与低能耗选型

- 最终路由器P0不缩水：现有所有启用且实际加载的机场节点自动发现；ChatGPT/Gemini/NotebookLM服务独立资格；全部真实合格节点入相应地区和全球池；原OpenClash成功订阅更新后增量维护；AI-only稳态选择和故障接替。Android/iOS智能P1；已有三端GitHub订阅转换、Worker与所有非AI规则不变。
- **订阅地址本身不能证明Google账号/NotebookLM平台放行**；Ping/ICMP、TCP、204测速仅证网络。Mihomo原生`fallback`/`lazy`健康探测可持续承担**基础网络**故障，尽量不重造监控。
- **正负按钮差异**：用户11/14 10:33宣传页`notebook.google`；10:34点击CTA后的`notebook.google.com/?icid=home_maincta...`并进工作台；10:45点击CTA后的`notebook.google/?location=unsupported`。一篇2026年10月公开独立网页亦直接检查该宣传页CTA超链接指向`https://notebook.google.com/?icid=home_maincta`（https://www.ai-jitan-hub.com/news/notebooklm-login-how-to-start-gemini-notebook-2026）；这是**无需执行JS就可直接GET的目标入口**，但未证实实际用户浏览器完整访问限制全部由这个GET决定。
- 一次未经登录的**外部公共网络**访问该固定URL，曾发生`accounts.google.com/ServiceLogin`跳转，说明不能把“HTTP响应/跳到登录页”判为该节点可用；也不是用户家中真实出口结果。
- Google官方Notebook帮助（https://support.google.com/gemininotebook/answer/16164461?hl=zh-Hans）说明地区、年龄/账号条件会影响可用；社区亦报告`location=unsupported`可能与IP、账号有关，绝不把一次阻断永久归责于某机场节点。

## 二、最省资源的建议生产策略（设计，未安装）

1. **订阅增量驱动**：使用原OpenClash的更新成功+正式Mihomo加载确认作为触发；枚举全部当期有效节点，不设总量上限。只将**新节点、同名改连接参数、证据过期或近期变差者**加入待测队列；未变节点继承**仍有效**的证明，不在每次订阅更新后重新全扫。
2. **常规低负载**：Mihomo原生按需/低频基础健康（可配置lazy、interval、timeout）；对正在用的AI主线和少量热备适当多测，冷备只按预算轮转，所有真正合格节点仍保留。
3. **NotebookLM轻量预筛**：只对通过基础网络检查且需要复核的节点，走该节点的独立、本地、已有/隔离的HTTP代理入口执行一次**GET**`https://notebook.google.com/?icid=home_maincta`；不用浏览器、不生成Cookie、不上传来源、不带Google登录态。只记录匿名结果：
   - `LIGHT_UNSUPPORTED_OBSERVED`：此次真实HTTPS重定向链明确见`location=unsupported` → **入口被阻断，不入自动可用池**，将账号/地区/出口等归因保留UNKNOWN，未来允许复检；
   - `LIGHT_LOGIN_PATH_CANDIDATE_UNVERIFIED`：试用入口HTTPS请求跳Google登录，**符合用户实测的支持节点积极分支**，可进入下一轮验证；但必须经真实正负节点GET对照校准，不等于已证明能够登录/导入来源；
   - `LIGHT_APP_HTTP_CANDIDATE_UNVERIFIED`：GET落到Notebook个人应用域名且HTTP200 → **只做后续业务测试候选**，不能单独升级`BUSINESS_VERIFIED`；
   - `LIGHT_MARKETING_ONLY`/其他超时、403、429、异常、未审核跳转 → UNKNOWN/类别保持。
4. **最终资格**：三服务分别须有实际登录与功能回执。NotebookLM至少真实工作区、非敏感来源导入、基于来源问答/引用核对和同一AI出口；即使GET成功也不能免除这道人工/授权实测门。在未经授权和设备实证前全部保持`BUSINESS=UNKNOWN`。HTTP无法低成本完成私人Google账号业务，因此“永远只靠Ping和订阅URL就得到全部真实合格节点”不可实现。
5. **节流建议**：每次刷新最多处理少量待测候选，失败延迟复测，缓存含**完整连接参数指纹、观察时间、会话/出口上下文**，不会永久漏掉合格节点；不启动常驻浏览器、不重新生成订阅地址。**具体并发/频率需经家中路由器实测资源后配置**，不能假称已有CPU/RAM/流量统计。
6. **隔离端口前提**：不允许为了轮测修改正在使用的AI父组或其他共用国家组。现新增一次性脚本**只使用已存在的隔离loopback HTTP代理入口**；它不会为每条机场节点创建此入口、不会开启或配置第二个Mihomo内核。当前尚未得到真实设备上的该入口与节点完整身份映射回执，故不能声称能扫描全部节点。

## 三、本轮可用的最小工具和已通过回归

- [脚本`scripts/ai_notebooklm_cta_light_probe.rb`](https://github.com/Kimbersy/openclash/blob/ffecde27978d774640724e72ec844aa74e4f5d5f/scripts/ai_notebooklm_cta_light_probe.rb)：Ruby+curl，**一次GET**，固定允许的CTA链接，已有本地隔离代理`127.0.0.1:PORT`，**12秒总超时、4次跳转上限、384KiB响应上限**，仅限HTTPS目标；临时响应头0600权限，退出自动删除；不显示URL、跟踪参数、IP、Cookie、节点凭据、账号或来源文本。只输出`NOTEBOOK_CTA=<匿名枚举> BUSINESS=UNKNOWN LIVE_WRITES=NONE`。仅带`--isolated-port=17881`等显式本地端口调用才会进行请求，无参数不会网络访问。无浏览器、无后台进程、无controller PUT、无订阅下载及生产配置写入。
- [Ruby回归`tests/test_ai_notebooklm_cta_light_probe.rb`](https://github.com/Kimbersy/openclash/blob/ffecde27978d774640724e72ec844aa74e4f5d5f/tests/test_ai_notebooklm_cta_light_probe.rb)：复现用户10:34入口分支/10:45阻断、无登录跳转假阳性、403/429/超时拒绝、恶意伪装域名/编码`unsupported`/无敏感URL输出；均为合成样本。
- 固定[Git `ffecde27978d774640724e72ec844aa74e4f5d5f`](https://github.com/Kimbersy/openclash/commit/ffecde27978d774640724e72ec844aa74e4f5d5f)和[CI #43549410059](https://github.com/Kimbersy/openclash/actions/runs/43549410059) `completed/success`，其中低能耗工具、原三AI真实业务门禁、全地区/订阅增量及三端非AI隔离回归均成功。这只证明测试输入、源代码结构和离线分类，不是Google真实节点是否支持的准入回执。
- 旧`scripts/ai_network_batch_once.sh`通过为每个索引短暂启动第二个隔离核心取网络证据，是旧式昂贵实验工具；**不应作为将来所有订阅节点的高频持续运行设计**。这轮新工具不会启动第二核心，但前置本地隔离代理必须另行验证。

## 四、最关键的下一步：校准低成本GET是否真的够用

不需要在路由器安装浏览器，也不要一口气扫58个。**选一条用户已确认“试用→icid→工作台”的真实节点和一条“试用→location=unsupported”的真实节点，在保证完整节点身份及相同用户网络出口的隔离环境中各做一次上述HTTP GET；比对响应跳转枚举是否能复现用户实测分支。**

- 如果正负样本区分清晰，才可把它作为**第一层**自动批量预筛、按增量队列轻量运行；
- 如果两者都只跳`accounts.google.com`、都200或因JS/登录状态差异无法分辨，就记录`PRECHECK_UNCALIBRATED`，不能将这个URL强行当成准入门，改用少量有界真实业务测试或经授权的低频浏览器/专用诊断方法；
- 未有真实节点对应的回执前**不发布名单、地区合格组，不启用自动切线**。P0全部有效节点覆盖、国家组、原订阅更新和故障接替仍是最终目标，不能因节能而缩水。

**唯一下一步：校准“现有隔离HTTP代理上的一次CTA GET”与两条已知真实按钮正负样本的对应关系，确认是否能完全不用浏览器做第一轮自动预筛；不要求重复旧58/58、AT_CLKTCK、已装更新器指纹。**
