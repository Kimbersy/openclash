# 2026-11-17 单次真实Mihomo活跃连接匿名同叶关联候选：CI PASS、未实机运行

## 固定源码与验收

- 固定[源码Git `9299bc8091723db2b32d852e658e49500c252b5e`](https://github.com/Kimbersy/openclash/blob/9299bc8091723db2b32d852e658e49500c252b5e/scripts/ai_runtime_leaf_inventory_readonly.rb)；[完整 GitHub Actions #44025550960](https://github.com/Kimbersy/openclash/actions/runs/44025550960) `completed/success`。原脚本**无参数**运行时，旧的`GET /proxies`匿名58条名字覆盖检查路径保持不变。
- 增加可选`--connections-source <测试设备的私有IPv4>`：当前**只在候选源码与CI验证，未给用户设备命令、未安装**。仅在用户平时正常使用AI服务期间一次性从当前唯一正式Mihomo的既有IPv4 Controller上以Bearer身份做**GET /proxies+GET /connections**。无HTTP外网探针，无服务流量人工重放，无PUT/DELETE、切换组、订阅刷新、核心启动或配置改写。
- 沿用已通过实机证明的唯一正式核心PID/NetNS/启动ticks和Controller真实socket所有权、当前运行配置选中源、最大3MB API回执与Ruby核心+设备已证的`psych`（仅此`require`）。查询后重新判断当前**仍只有同一个核心**、同一核心身份和相同监听socket；任一条件变化保持HOLD。
- `GET /connections` 的JSON可能含其他家庭成员的域名/IP/进程/路径/连接明细，原始内容**只在本地Ruby进程内用于分类**；不会打印、保存、上传、写到GitHub、复制到聊天或公开报告。输出仅每平台匿名`OBSERVED_ONE_LEAF_CANDIDATE/HOLD_*`和整体`SAME_LEAF_ANONYMOUS_CANDIDATE_ONLY/HOLD_*`。不得输出测试设备内网IP、节点名称、实际域名、node/server/password、API密钥、TLS参数、chain或完整raw JSON。
- 必须明确指定所测家庭设备的私有IPv4/CGNAT来源（不能从其它家庭设备同网站流量暗中猜测来源），并对目标精准匹配`chatgpt.com`及合法子域、`gemini.google.com`、`notebooklm.google.com`，拒绝lookalike后缀、host/sniffHost不一致及非字符串冲突。未匹配服务时不会伪称测试失败，仅`HOLD_NO_ACTIVE_CONNECTION`（因为`/connections`仅瞬时活跃，用户可能已完成会话）。只允许`🤖 AI`真实组在chains上，必须有且只有一个**当前配置内**完整已命名叶、链中不得出现DIRECT/未知组/多叶；同平台多条活跃连接指向不同叶、三平台各用不同叶都HOLD。
- `GET /proxies`必须先通过原脚本的当前配置/正式API的全量叶名称覆盖门禁；但**仍不能用名字覆盖证明核心内存完整认证/传输参数指纹**，任何同叶仅作为候选。本功能特别标记`SAME_LEAF_AUTHENTICATED=NO LIVE_FULL_CREDENTIAL_FINGERPRINTS=NOT_VERIFIED DUAL_PUBLIC_IPV4_EXIT=NOT_VERIFIED BUSINESS_VERIFIED=NO ALLOW_RECONCILE=NO ALLOW_SWITCH=NO`。
- 合成测试包括不同LAN设备、缺源IP、无活动连接、多个不同叶、DIRECT/不属于AI组、未知链、冲突域名、被伪造后缀、子结构损坏、core唯一性变化、原始密钥/设备IP/节点/访问域名绝不出现在stdout、旧no-args入口保留及iStoreOS无额外Ruby依赖。CI全量P0/三端非AI回归已通过。

## 已知真实回执全部沿用

- 用户明确报告并确认：ChatGPT/Gemini/NotebookLM现在经家庭iStoreOS/OpenClash出网、当前正常使用。不能以此认为NotebookLM每项工作流或58条节点均获业务资格证。
- 2026-11-15实机：08:55短fork/setsid回收PASS、08:28设备本地04点更新预约UCI、23:59前台观察器baseline PASS；更早58/58正式源/核心**磁盘完整字段**一致、核心运行API节点名字58/58、20规则Provider正数。旧设备验收不重跑。
- 2026-11-17已修复双来源公网IPv4漏洞，固定Git`7c6b8f89`与CI`#43988199179`。但当下**没有**实际对同叶公网IPv4地区进行外网双来源验证。

## 证据边界与唯一下一步

**本轮已完成工程候选及完整CI；并未实机运行新GET /connections**。现有脚本不能认证正式核心内存中的完整私密传输指纹、也不能证明某次订阅远端成功提交加载。即使观察到三个网站同叶，也仅是**瞬时相同叶名称和链路候选**；无法从它本身核验相同真实公网IPv4地区/长期业务资格，不能直接触发AI自动选线或备用接管。

**当前唯一下一步（一次真正有证据价值的实机试点，条件满足才实施）**：先从既有已授权的终端网络状态确定**实际测试客户端的内网IPv4**，并保证正常使用AI时确有活跃连接，然后用此固定SHA跑一次前台匿名`--connections-source`读取（不要求重复登录/导入/重新考三个平台；若没有自然活跃连接可HOLD而不循环重试）。如无法明确客户端内网IP/连接来源，先不发无法执行的占位命令；不能根据`🤖 AI`父组的`now`自行假设服务使用哪条叶。取得真实同叶候选后，才值得决定**同一叶隔离CONNECT出口**的双独立公网IPv4国家实测是否需临时监听器及用户授权。所有阶段不写当前配置、不接入订阅更新Hook/后台观察器、不影响非AI/三端/Worker，AUTO_SWITCH OFF，VPS HOLD。
