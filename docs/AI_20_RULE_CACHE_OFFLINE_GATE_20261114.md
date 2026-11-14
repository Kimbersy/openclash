# 20/20 HTTP Rule Provider 本地缓存：低能耗、离线验证候选（2026-11-14）

> **阶段状态**：用户真实缓存清点已通过；20份真实缓存均可定位，但**未读取/哈希校验内容**。本轮仅在GitHub用**合成缓存与合成节点**验证私有`type:file`规则解析及AI-only Listener，**真实路由器未跑新测试、原有HTTP Provider和Geo设置未修改**。

## 真实设备回执

用户在iStoreOS TTYD执行[固定 `b5d9ced`](https://github.com/Kimbersy/openclash/commit/b5d9ced83925768860f1aa2ada3834c84571f5e2)后返回：
```text
INVENTORY_RESULT=RULE_PROVIDER_SHAPE_CLASSIFIED
RULE_PROVIDER_TOTAL=20
TYPE_HTTP=20 TYPE_FILE=0 TYPE_INLINE=0 TYPE_UNKNOWN=0
CACHE_LOCAL_REGULAR=20 CACHE_MISSING=0 CACHE_NO_EXPLICIT_PATH=0
CACHE_OUTSIDE_HOME=0 CACHE_UNSAFE_PATH=0 CACHE_UNVERIFIED=0
BUNDLE_DEPENDENCY=0 RULESET_REFERENCE_PRESENT=1 GEO_REFERENCE_PRESENT=0
GEO_MODE_ENABLED=1 PROXY_PROVIDERS_PRESENT=0 GROUP_PROVIDER_USE_PRESENT=0
PRIVATE_COPY_TEST=NOT_RUN RULE_CONTENT=NOT_READ
PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AI_AUTO_SWITCH=OFF
```

这证明本机有20份显式路径、处于当前Mihomo HomeDir内、无发现symlink或失踪的本地规则文件；它**不证明缓存实际被运行态Mihomo加载、内容合法、更新新鲜或与当前规则内存完全一致**。`GEO_MODE_ENABLED=1`是旧脚本三项OR（`geodata-mode==true`、`geo-auto-update==true`、出现`geox-url`），**不能直接说已证`geo-auto-update`开启**；需要再分清，但不再要求用户重跑旧统计。

官方[Mihomo Rule-Providers](https://wiki.metacubex.one/en/config/rule-providers/)说明http/file/inline三类、behavior/format约束、路径受`-d` HomeDir约束；`http`可能下载或更新。官方[通用GEO配置](https://wiki.metacubex.one/en/config/general/)区分GEO dat模式、自动更新和自定义下载地址。

## 本轮新交付：纯离线20份缓存完整模拟

- 固定源码 [`545c78cd0518526478adcc5035faa71db024c0a6`](https://github.com/Kimbersy/openclash/commit/545c78cd0518526478adcc5035faa71db024c0a6)，完整[GitHub Actions #43576991210](https://github.com/Kimbersy/openclash/actions/runs/43576991210) `completed/success`。
- [`scripts/ai_ruleset_cached_offline_overlay.py`](https://github.com/Kimbersy/openclash/blob/545c78cd0518526478adcc5035faa71db024c0a6/scripts/ai_ruleset_cached_offline_overlay.py)：**纯内存**入口，接收合成或已被外部校验的源结构/缓存字节，不运行在iStoreOS；只有20份一一匹配、http类型、显式安全路径、有效behavior/format与缓存字节大小上限等门禁满足时，生成**测试副本专用**`type:file` Provider并映射到独立`test_rule_cache/`，原有Provider的**名字、规则引用、behavior/format及字节内容保持一致**。原输入字典保持不变；原DNS、节点、非AI分组、原`🤖 AI`选择和其它配置保持不变；只追加专用`REJECT`首项select和`127.0.0.1:17881` Listener。
- [合成回归](https://github.com/Kimbersy/openclash/blob/545c78cd0518526478adcc5035faa71db024c0a6/tests/test_ai_ruleset_cached_offline_overlay.py)：20份/80份源全保留、缺项/缓存长度/总预算、私有令牌不出状态、相对路径越界、provider类型/格式/来源错误、`proxy-providers`/共享组引用及Geo任一风险均HOLD。
- [20份合成缓存fixture](https://github.com/Kimbersy/openclash/blob/545c78cd0518526478adcc5035faa71db024c0a6/tests/make_ai_cached_ruleset_native_fixture.py)：`20`个合成http Provider、全部缓存一致，以`file`测试模式生成规则与附加AI入口；**上游官方Mihomo v1.19.34真二进制**在GitHub CI执行`-t`成功（同一Workflow中原有跨端、非AI冻结回归通过）。
- **解释边界**：私有临时`type:file`解析成功≠用户现有`type:http`的下载/更新行为成功，更不意味着能把生产HTTP Provider转换为file。GEO配置仍被候选明确`HOLD_GEO_RESOURCE_NOT_MIRRORED`，没有允许当前真实配置直接`-t`。无网络隔离验证之前不把“没有调用curl”当作Mihomo子进程绝不联网的证明；本轮没有在真实路由器启动任何原生测试或复制缓存。

## 唯一下一步

先在候选分支规划**实机Geo配置匿名细分和只在本机的安全缓存字节复制**：判断`GEO_MODE_ENABLED=1`到底来自`geodata-mode`、自动更新还是自定义URL；按Geo资产/更新依赖明确`HOLD`，绝不绕过下载风险。若能构成无外部动态资源的受保护私有副本，才安排一次低负载真实设备校验：20份缓存单个限额和总限额、逐文件复制后字节对比、原规则引用/非AI结构复核、临时目录清理；没有证明隔离情况下绝不自发下载就**不能**在路由器跑真实配置`-t`。即使通过，正式增加Listener仍需用户明确授权、备份及运行态REJECT回读。

P0不变：全部启用订阅真实合格节点、ChatGPT/Gemini/NotebookLM独立业务池、实际出口地区动态组、随现有订阅增量同步、稳态故障接替；Android/iOS智能化P1，所有原有规则转换/Worker/非AI不动。NotebookLM`unsupported`/icid还是入口预筛，最终需要真实导入来源、问答、引用与同出口。
