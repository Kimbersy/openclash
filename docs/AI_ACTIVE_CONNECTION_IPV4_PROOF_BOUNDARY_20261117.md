# 2026-11-17 家庭AI正常使用后的同叶连接与真实IPv4出口证据审查

## 已取得的真实业务与范围

- [用户确认](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_THREE_AI_USER_REPORT_20261117_0727.md)：ChatGPT、Gemini、NotebookLM **当前正常使用且经家中 iStoreOS/OpenClash 出网**，这是家庭路径用户实际体验的正面证据；并**非三平台完整工作流自动验证、58条节点全量合格或当前同一叶节点身份已认证**。
- 复用先前实机：源/正式运行配置磁盘58条全字段一致、运行API 58条**名字覆盖**、20条规则Provider正数、一个启用订阅源每日设备本地04点设置。以上不能替代核心内存**完整私有连接参数**验证或某次远程订阅下载/合并/加载成功回执。
- 当前AI自动切组关闭，`ALLOW_RECONCILE=NO ALLOW_SWITCH=NO`，生产OpenClash、三端、Worker与非AI维持不变，VPS HOLD。

## 本轮发现并完成的 P0 IPv4 错误修复

- 原`scripts/audit_egress.py`的两个来源交叉验证只比较`source / ip / country`一致性，**没有检查IP地址版本或公网路由能力**。因`ipapi.co`本身同时支持IPv4和IPv6，存在双方同报IPv6（或保留/私有地址）却判`egress_verified=True`、把“任何IP证据”误当P0**公网IPv4**证据的安全逻辑漏洞。
- 已在固定[Git `7c6b8f89b1f7316e1acb2a7e3414e9779206861a`](https://github.com/Kimbersy/openclash/commit/7c6b8f89b1f7316e1acb2a7e3414e9779206861a) 修复：HTTP返回地址必须`IPv4Address`且`is_global`；`classify()`也独立验证恰好两条有效响应、各来自不同`ipinfo/ipapi`、错误列表为空、**同一个公网IPv4**、同一个两位国家码才可`egress_verified=True`。IPv6（包括IPv4-mapped IPv6）、局域网、环回、RFC5737示例地址、异常来源、重复来源及错误均保守`unknown/HOLD`，国家显示与节点昵称不一致仍可保留真实观测国家，不误判为不可用。
- 对真实代码和合成反例添加回归，固定[完整CI #43988199179](https://github.com/Kimbersy/openclash/actions/runs/43988199179) `completed/success`，包括原三端/非AI/P0和精简iStoreOS门禁。**这仅是Git/CI通过，没有执行任何真实地理位置查询、扫描58条节点或修改家庭网络**。
- [官方IPinfo IPv4/IPv6文档](https://support.ipinfo.io/hc/en-us/articles/30792495690642-Does-IPinfo-Support-IPv6) 说明通用接口可能优先IPv6；[ipapi官方文档](https://ipapi.co/api/)明确支持两地址族。保持现有两个独立服务，但协议族不符时诚实HOLD，绝不能从单源/标签补作合格。
  
## 可复用的实时控制接口及其边界

- [Mihomo官方API文档](https://wiki.metacubex.one/en/api/)：`GET /connections`只读返回**当前活跃连接**的`metadata`、`chains`、`providerChains`、`rule`、`rulePayload`，并不保留离线历史；`GET /proxies`返回组的`now`和代理清单，但不能单独证明**每一条特定服务连接**实际用了该叶。二者都**不返回正式核心内存中完整认证/传输私密参数指纹**。
- 仓库现有`scripts/ai_runtime_leaf_inventory_readonly.rb`已实机PASS的权限边界值得复用：找唯一正式核心PID和配置、确认Controller TCP socket由该核心持有、仅访问`127.0.0.1` IPv4并以本地有效Bearer进行**GET /proxies**，且绝不输出私有节点名/明文配置/密钥。**现有脚本并未实现`GET /connections`，不能说已可自动核验三AI的实际路由。**
- 业务同叶关联还缺**用户活动对应时刻**的匿名连接快照：只观察明确域名（如`chatgpt.com`、`gemini.google.com`、`notebooklm.google.com`）对应的当前`chains`，同时关联家庭具体测试设备源IP（该私有IP只用于本机内部验证，不能公开），处理缺失host、登录跨域、SniffHost冲突、多层代理链/多叶跳点、非AI group、API空连接时统一HOLD，不可简单把`GET /proxies`的`now`套到三个服务上。
- 单一叶的真实IPv4国别还须使用现有`scripts/audit_egress.py`的**同叶隔离HTTP CONNECT监听器**向ipinfo/ipapi分别发起真实请求。**普通浏览器分别打开两网站不保证它们与AI域名同一叶；匿名连接快照也本身不代表节点IPv4公网出口**。当前没有合格的生产可用隔离监听器被安装、也没有可用的实时私有证据，绝不声称国别已验证。
- **采集隐私风险**：`GET /connections`还包含全部终端的域名、源IP、进程和连接时间，原始API JSON不能贴给ChatGPT、不能上传GitHub、不能写公共日志；以后只允许输出经严格白名单+唯一叶身份校验后的匿名统计/状态码，且不得对其它家庭用户连接做原文记录。
- **分级结论**：当前`HOME_ISTOREOS_PATH=USER_CONFIRMED`、`AI_FUNCTIONAL_NORMAL=USER_REPORTED`。`SAME_LEAF_FOR_THREE_SERVICES=NOT_VERIFIED`、`LIVE_FULL_CONNECTION_FINGERPRINTS=NOT_VERIFIED`、`DUAL_INDEPENDENT_PUBLIC_IPV4_COUNTRY=NOT_VERIFIED`、`SUBSCRIPTION_REMOTE_COMMIT_AND_LOAD=NOT_VERIFIED`、`AUTO_SWITCH=OFF`。

## 唯一下一步（工程端，仍不让用户执行无意义设备命令）

优先在**已经实机验证的单文件Ruby/controller归属校验/匿名输出流程**之上评估**一次性的、严格只读`GET /connections`私有同叶匿名判定入口**是否真有价值，并先补离线反例：域名冲突、多叶、DIRECT、缺失源设备、空连接、其他家庭用户的同域流量、socket-owner或core PID变化、一条服务跨多个不同叶、意外完整JSON敏感输出。只有具备可信身份/隐私/性能边界且原有三端/P0全量CI通过，才能提出**在用户正常使用期间**一次固定SHA受控验收，不要求专门重复三AI完整功能测试，更不能将此与真正双源IPv4出口的隔离验证混为一项。

如果这一步必须新增本地监听器/代理出口，先提供具体影响、回滚和明确授权；否则保持HOLD，不在生产加长期后台、不扩展无业务价值监测。已修复的公网IPv4验证逻辑不重做，VPS仍暂缓。
