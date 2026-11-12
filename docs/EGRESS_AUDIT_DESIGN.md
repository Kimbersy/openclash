# AI 出口事实、服务可用性与稳态候选（尚未部署）

更新日期：2026-11-12。**所有变更仅在 Draft PR #2 候选分支；正式订阅、OpenClash 设备、Cloudflare Worker/KV 均未更改。**

## 最初需求与这次纠偏

用户要解决的是 AI 节点使用不稳定、自动误切、机场名义位置与真实公网出口不一致，以及 OpenClash/Android Mihomo/iOS Shadowrocket 配置统一维护。台湾只是一个举例，**不能设计成只检查台湾，也不能按照国家推测服务全部可用或不可用**。用户的现状反馈是：一些标称香港节点通过机场分流可以使用 ChatGPT，但 NotebookLM 不可用。它是个别节点和服务的实测经验，**不是整个香港地区的通用结论**。

每个节点须独立维护三种事实：

1. **机场声称地区**：从名称尝试识别，可能缺失、含糊或错误，仅作对照。
2. **实际出口地区**：通过该节点分别访问至少两家公网 IP/GeoIP 回显来源，只有 IP 与国家一致才标记 `egress_verified=true`、填入 `observed_country`。名称写台湾但出口香港的节点保留、标为 `mismatch`，**按真实香港出口归类，不应直接删除**；名称不含地区但出口核验成功的节点也保留。不能把 `gstatic 204` 连通性当成实际 IP 的地理证明。
3. **服务级实际可用性**：ChatGPT、NotebookLM、Gemini 分别记录；同一节点可 ChatGPT 可用而 NotebookLM 不可用，或反之。出口地区、测速、HTTP 连通性都不能代替登录后的真实 AI 会话/页面功能验证。未实测时标记 `unknown`，**绝不凭国家给全部服务一票通过/否决**。

### 新候选行为

- `scripts/audit_egress.py` 为每个节点输出 `claimed_country`、`observed_country`、`status=match/mismatch/unknown/inconsistent`、独立的 `egress_verified`，以及初始空对象 `service_availability={}`。双源冲突/无法完成访问：不发放实测出口资格。新字段 `observed_exit_name_filters` 包含所有核验成功的实际出口（也包括名称不符或没有国别名称的节点）。
- `scripts/render_verified_candidate.py` **按 observed_country 生成** `🧭出口🇭🇰香港`、`🧭出口🇹🇼台湾`、`🧭出口🇯🇵日本`、`🧭出口🌐CA` 等可选策略组：并不限于某几个硬编码国家。香港出口也可以作为 ChatGPT 的**人工候选**，但这并不保证 NotebookLM、Gemini 可用。
- 原 `🤖 AI` `select` 的已有选项/顺序不改变，只在末尾追加新出口备选；视频、YouTube、Disney+、GitHub 和其他既有规则不改变。Mihomo 与 Shadowrocket 均来自同一 `Clash-Li.ini` 和原有生成器，精确节点正则继续保留完整锚点。
- **删除之前仅为台湾生成的 `🛡️AI 稳态🇹🇼台湾` 自动 fallback 候选**。没有单项服务实机合格节点与长连接数据之前，任何国家都不默认获批 AI 自动备援。之后可按 `ChatGPT`、`NotebookLM`、`Gemini` 各自的合格池设计可选的主备与切换冷却，绝不因为国别相同就合并服务策略。

### 服务级验收设计（待真机实施，不凭模拟结果放行）

| 维度 | 真实核验方式 | 记录 |
|---|---|---|
| 出口身份 | 独立节点本地 HTTP CONNECT → ipinfo、ipapi；记录公网 IP/国家是否双源相同 | `observed_country`, `observed_ips`, `egress_verified` |
| ChatGPT | 用同一指定节点在真实客户端登录并实际发送/接收消息，观察响应、登录或地区错误 | `usable/unusable/unknown` + 终端/时间 + 错误类别 |
| NotebookLM | 用同一节点实际打开工作区并完成一次用户允许的普通交互 | 独立的 `usable/unusable/unknown` |
| Gemini | 同一节点完成真实页面/会话请求 | 独立的 `usable/unusable/unknown` |
| 稳定性 | 不频繁切换的时间窗内观察会话、切换次数、恢复时长和失败次数，并在不同时间复测 | 实际切换/断流/恢复统计，不能仅凭延迟 |

平台可用性受账号、地区政策、机场二次分流、DNS 等因素影响；一条 HTTPS 204 或页面可连接只证明局部连通性。没有实际业务证据时，任何服务标记均保持 `unknown`。真实 IP 也可能因机场运营调整而改变，检测结果须设有效期并复测。

## 如何在家庭路由器安全完成真实出口检测

现有 iStoreOS 旁路由 `x86_64`、内存 `MemAvailable≈1100MiB`，OpenClash `v0.47.156` + Mihomo `alpha-ge183c58` 正运行，`ruby` 与 `curl` 可用，宿主 Python 未安装；`/etc/openclash/core/clash_meta` 存在可执行。2026-11-12 14:46 真实 UCI 返回 `UCI_ACTIVE=CONFIG_2`，该私有 YAML 含58个内嵌节点；另一未选中配置含169个条目。**58个节点是否在线或支持各平台仍未实测**。

- 第一步仅对这58个节点做**所有地区**的匿名分布统计，包含香港、台湾、日本、新加坡、美国、韩国、欧洲以及不可识别标签；名称只是“候选采样”，不能判定真实出口。可优先抽取香港、台湾、日本及不含国别的少量节点，不能只查台湾。
- 确认资源与监听隔离后，在路由器上通过**额外独立进程**和临时目录运行有限并发逐节点检测；不能改动现有 OpenClash 内核进程、AI 选择、DNS、TUN 或其他家用服务。应先证明用到的独立 listeners 和端口没有影响当前网络，并设置资源限制/回收。
- 公共代码的 `scripts/prepare_isolated_audit.py` + `scripts/audit_egress.py` 是候选实现，离线模拟 CI 已通过。路由器宿主没有 Python；已确认 Ruby/Psych 可读取私有 YAML，因此后续可仅在路由器本地生成同等隔离配置或复用可信现有运行环境。**不要求用户将机场 URL/订阅、节点密码、完整私有 YAML 或公网 IP 清单发进聊天/GitHub**。
- `audit_egress.py` 当前只探测 IP/国家，**不执行服务可用性验证**。后续服务级检测必须另有可信终端真实回执，且服务失败不得归咎于国家或节点标签本身。

参考上游 Mihomo [listeners](https://wiki.metacubex.one/en/config/inbound/listeners/) 和 [proxy group](https://wiki.metacubex.one/en/config/proxy-groups/) 文档。标准 fallback 仍可能在故障/恢复时切换，切线会使 AI 长连接中断，不可把 600s/10s 当成会话保持保证。

## 私有性、回归和发布条件

- 私有节点数据、密钥和 GeoIP 详情只能保留在路由器/授权的私有系统。公开 GitHub CI 使用模拟数据，不访问真实机场或任何用户 AI 账号。
- 已有 `Clash-Li.ini`、`list/AI.list`、`generated/` 及真实客户端订阅**不被 Draft PR 自动修改**。旧版选择和正常 YouTube、网页、Disney+ 流量必须通过回归。
- 即使跨端生成测试全部通过，也**不能宣称**真实 IP/业务稳定性已验收；需要家庭线路上的有限真实节点出口测试与 ChatGPT/NotebookLM/Gemini 的分别验证，然后在私有渠道下发测试配置并验收 Android/OpenClash/Shadowrocket。
- 真正需要按服务独立路由时，必须先验证规则优先级、实际 UI 组选择和必要的服务域名规则，避免破坏现有总体 `🤖 AI` 策略。只有连续稳定性证明足够，才考虑按服务开备援或冷却策略。
- VPS 只在已有机场无法满足这些业务指标时再评估，不将新增海外服务器当默认前提。

## 唯一下一步

继续从已确定的 UCI 活动 CONFIG_2 私有文件出发，**一次统计全部58个节点的标称地区分布与未知类（不暴露名字）**，据此从多地区抽取有限样本，准备真实双源出口 IP 核验。后续服务级检测单列，不凭地区猜可用性。当前保持 PR Draft/unmerged，现网不变。
