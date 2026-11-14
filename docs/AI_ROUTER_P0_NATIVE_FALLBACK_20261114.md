# 路由器 P0：AI 专用原生 fallback 最小候选（2026-11-14）

**状态：候选源码及合成 CI PASS；未安装、未修改任何家用设备、未做业务/真实故障回执；绝不写成已交付。**

## 最终目标与本轮小验收

P0：利用现有 iStoreOS/OpenClash + 动态机场订阅，让 ChatGPT、Gemini、NotebookLM 的 AI 流量能够选经真实业务验证的主线，故障时在合格备用间接替。不得改变国内、Disney、流媒体、GitHub、Telegram 等非 AI 分流，也不修改当前手机订阅、Cloudflare Worker/KV。安卓和苹果智能功能属于可选 P1，不能阻塞路由器。

本轮只做**可交给 Mihomo 内核测试的离线 AI 专用候选组构建器**，不新建调度进程、测速框架或订阅转换器。

- [x] 复用现有 `reconcile_subscription` 的完整节点指纹、`ai_service_stability_dry_run.qualified_pool` 的三服务真实业务资格及最新地区/健康证明筛选；最多 3 条有独立指纹的叶节点，至少 2 条（1 主+1 备），与未信任额外1条代理隔离。
- [x] 只新增 **`🛡️AI·路由器自动主备`**，类型为 Mihomo 原生 `fallback`，节点按稳定性优先；`url=https://cp.cloudflare.com/generate_204`、`interval=300`、`lazy=true`、`timeout=4000`（仅网络层健康参考，**不等于已证明三个AI业务成功**）；候选限制为直接叶代理，防止嵌套组影响其他业务。
- [x] 只在现有 `🤖 AI` **人工 select 组末尾增加一个候选选项**，默认/已有成员及顺序不变。旧用户当前人工选择不被切换；只有后续获得许可并在路由器上主动选择此新项，才触发新fallback。
- [x] 不修改 `rules`、`rule-providers`、`proxy-providers`、`proxies`、`dns`、任何非 AI 策略组、`secret` 或其他顶层配置，不接触共享GitHub配置源；若用户当前已装核心不认该候选格式，必须停并回滚。
- [x] 旧的完整节点身份改变、业务证据未全通过/过期、地区证据缺少双源、健康样本不足/超时、已有策略组名称冲突、节点名不在活动目录、未来provider模式与当前来源不相符或独立来源/运行证明缺失时，**保持原配置，输出匿名HOLD**。候选资格/源完整运行可信证明需来自受保护的实际运行资料；单纯调用带`True`的参数不构成独立证明。
- [x] CI使用虚构TLS密码和虚构域名，覆盖NotebookLM来源导入未通过、403/静态HTTP不能冒充业务、同名改密码、TW地区锁、58+未知额外、人工选择不变、所有非AI字段完全一致、只有模拟服务全合格时生成主备；**无真实机场名单写进仓库**。

## 固定代码及测试

- [候选源码 `scripts/build_router_ai_p0_candidate.py`](https://github.com/Kimbersy/openclash/blob/c70810bba9b90cd4b46373f0ee9b6b4e19234d2c/scripts/build_router_ai_p0_candidate.py)
- [回归测试 `tests/test_build_router_ai_p0_candidate.py`](https://github.com/Kimbersy/openclash/blob/c70810bba9b90cd4b46373f0ee9b6b4e19234d2c/tests/test_build_router_ai_p0_candidate.py)
- [固定 Git `c70810bba9b90cd4b46373f0ee9b6b4e19234d2c`](https://github.com/Kimbersy/openclash/commit/c70810bba9b90cd4b46373f0ee9b6b4e19234d2c) / [Actions #43539389671](https://github.com/Kimbersy/openclash/actions/runs/43539389671) completed/success。新增`Router P0 independent AI-only fallback and non-AI invariance regression`、既有Android/iOS共享生成隔离测试及整个候选CI均通过。**这是合成/源码回归，不是iStoreOS实机验收。**

## 清晰的交付缺口（不围绕细节无限延伸）

1. 真实设备的**当前**订阅节点指纹和真实三平台业务资格尚无可用「一主一备」回执；历史09/10/01仅用于寻找候选，不能自动相信其现在仍存在、出口不变或NotebookLM可工作。
2. 并未在当前正式Mihomo核心上独立执行配置语法校验、实际fallback双节点失效试验或非AI对照；此前的只读API 58/58名字+额外1不证明完整节点连接凭据已载入。
3. 原生fallback按HTTP网络探测自动接替，**不会识别AI账号429/Google地区403/NotebookLM导入失败**；不能拿它冒充完整AI智能监控。是否需要额外只读监控，应根据真实主备试点观察决定，而不是为插件而加插件。
4. 动态订阅更新后，如果主备节点身份变化，资格必须撤销并重新验证；当前仅纯函数具备身份防护，尚无可安全下发候选的可信自动发布闭环。**因此本轮不得在正式设备启用常驻自动切换**。
5. 当前路由器原配置人工选线与非AI保留，Clash Mate/Shadowrocket的P1智能增强并未修改，VPS未采购。

## 唯一下一步（以业务交付为中心）

**在受控、可回退的路由器试点里，仅对当前AI主线和最多两个历史候选中身份仍一致者，取得至少两条节点的 ChatGPT 登录+生成/流式、Gemini 登录+真实回答、NotebookLM 工作区+非敏感来源导入+问答回执。** 之后用对应的受保护本地配置副本测试这一平坦fallback在Mihomo内核真实`-t`和故障时能否从主切备、恢复后是否抖动，并核对非AI流量零行为变化。需要变更正式设备时另做版本固定、配置备份、最短人工启用和即时回滚。**在没有业务资格前不假装已有合格主备，也不要求用户重新扫描全部58节点。**
