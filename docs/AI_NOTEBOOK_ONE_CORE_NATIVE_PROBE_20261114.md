# NotebookLM低能耗节点逐条检测：Mihomo原生单核单入口方案（2026-11-14）

> **证据分级**：官方文档已核实 + 固定源码合成回归 + **官方Mihomo v1.19.34二进制原生`-t`配置校验已通过**；未在用户家中iStoreOS加载新监听端口、未对任何真实节点做NotebookLM HTTPS请求、未确认实际家中核心版本或端口占用。**本报告不能被视为P0部署/Google业务合格。**

## 为什么采用单核原生隔离入口

目标不是重建一套订阅/智能控制器，而是使现有`scripts/ai_notebooklm_cta_light_probe.rb`能够在**不切换日常`🤖 AI`人工线路**的情况下访问指定节点。

- [Mihomo官方inbound/listeners文档](https://wiki.metacubex.one/en/config/inbound/listeners/)明确：`listeners[].proxy`非空时，指定这个入站流量**直接交给该代理/策略组**，不经过通常`rules`；监听地址可设`127.0.0.1`。这使一个HTTP入站端口和一个独立的`select`组可定向到指定叶节点，**只复用已运行的一个Mihomo内核**。
- [官方Mihomo API说明](https://wiki.metacubex.one/en/api/)确认单节点`GET /proxies/{name}/delay`只返回延迟值（含`expected`状态选择），**不返回HTTP Location重定向链**。所以原生测速可当基础网络健康检查，但**不能替代NotebookLM的`location=unsupported`跳转识别**。对后者仍需要短时经指定叶节点的真实HTTPS GET。
- 旧工具`ai_notebooklm_cta_light_probe.rb`每次固定CTA URL、仅一个GET、12秒总超时、4次跳转、384KiB响应限制、匿名枚举结果（`unsupported`、Google登录积极候选、其他未知），不会自动授权`BUSINESS_VERIFIED`。对用户已观察的Chrome点击CTA正/负两支，**尚未校准自动GET是否与浏览器一致**。

## 本轮新增最小原生配置候选

候选源码：[`scripts/ai_notebook_one_core_probe_candidate.py`](https://github.com/Kimbersy/openclash/blob/79cf5917214034fb246cd48d2bd44859e7db9083/scripts/ai_notebook_one_core_probe_candidate.py)，[独立合成配置](https://github.com/Kimbersy/openclash/blob/79cf5917214034fb246cd48d2bd44859e7db9083/tests/make_ai_notebook_native_mihomo_fixture.py)。只有一个隔离监听器，默认`REJECT`，并非额外常驻浏览器、监听所有LAN、第二个内核或新定时扫描器：

```yaml
# 仅结构示意，尚未进入家中生产配置：
proxy-groups:
  - name: __AI_NOTEBOOK_PROBE_ONLY__
    type: select
    proxies: [REJECT, '<全部当前已核对身份的有效叶节点>']

listeners:
  - name: ai-notebook-probe-only
    type: http
    listen: 127.0.0.1
    port: 17881
    proxy: __AI_NOTEBOOK_PROBE_ONLY__
```

- 原`🤖 AI`、原国家组、Disney、GitHub、普通规则、`proxies`、DNS、Controller Secret及手机订阅 **全部保持原值**；仅在候选配置副本尾部添加一个用于探测的select和一个本地listener。内部`REJECT`排在第一项，在没有明确选定测试叶之前不能发起成功代理请求。
- 没有“只3条”上限，合成70个节点也全部列入独立待测目录，**不等于它们已合格**。用户P0最终仍是**所有已启用且实际生效订阅源**及未来Provider的动态发现/验证/分地区/订阅增量/稳态接替。
- 拒绝没有可信来源身份证明、已有组名/叶名/端口冲突、不可识别的listener端口/节点类型、非空Provider没有完整运行身份证明的输入。**这些是源码层HOLD，实际Mihomo是否已加载完整凭据仍需另外验证**。
- 只有**将来另行受控配置灰度**后，单次测试才可能：对**专用探测组**选指定节点并通过GET回读验证；使用专用localhost端口发CTA GET；立即把**专用探测组**复原到REJECT并回读。任何Controller写操作都**不得**修改公共`🤖 AI`/国家/媒体组。**本轮并未实现或调用这些Controller写操作**，也没有加入实际计划定时器。

## 已通过的固定校验

- [固定代码 Git `79cf5917214034fb246cd48d2bd44859e7db9083`](https://github.com/Kimbersy/openclash/commit/79cf5917214034fb246cd48d2bd44859e7db9083)。
- [GitHub Actions #43552254288](https://github.com/Kimbersy/openclash/actions/runs/43552254288) `completed/success`：
  1. 纯函数/合成回归：单核一端口默认REJECT、原AI组和非AI全量不变、端口/组冲突HOLD、未来Provider不能悄悄忽略、70个合成叶节点不截断、产物不泄漏凭据，均通过；
  2. 使用上游2026-11-11官方[Mihomo v1.19.34 Linux amd64 compatible](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.34)，按官方资产`SHA256=2763f5b414527f7baf6dc57e3f82f3ab561eedf34bfd7c2f2cde1f7e592efe06`校验下载后，对本工程生成的合成新配置执行**真正`mihomo -t -f config.yaml`，返回成功**；
  3. 原三AI业务/Notebook CTA分类、全订阅/地区增量、Shared Android/iOS 和非AI冻结回归均Success。
- **未核**：家中正式Mihomo版本不等于官方新版验证环境；0.47.151是用户安装的**OpenClash更新脚本**对应上游版本，不能当成内核版本。现有端口17881是否有别的服务监听/防火墙行为、如果从LAN错误暴露、运行态目录完整凭据一致性、专用组Controller写后是否能GET回读、真正正负节点CTA结果和回滚，都必须由对应实机回执证实。

## 下一阶段最小授权与验收，不在细节无限延伸

**当前唯一下一步**：在原有OpenClash路由器**只读取**实际Mihomo核心版本、当前在用配置的已有listeners/代理端口与`127.0.0.1:17881`占用、当前有效叶节点与其私有指纹映射（不要外传凭据），对照本轮固定候选。若没有碰撞/缺口，用当前已装内核对**受保护的本地配置副本**执行原生`-t`，保留结果和回滚方案；涉及真正新增listener及仅改私有探测select的Controller操作，须向用户集中说明并取得明确许可。只有安全灰度完成，才在此隔离端口对已知1条NotebookLM支持和1条unsupported节点进行**一次性HTTPS GET正负校准**，并核对专用入口选的是相同真实叶节点/出口。若两节点GET都只跳登录、不区分，停止使用这条轻量路径为“资格筛选”，仍需少量有界真实浏览器业务测试。

最终`BUSINESS_VERIFIED`仍需NotebookLM真实登录/工作区/来源导入/引用及同出口，不能以这次`mihomo -t`或入口阳性冒充P0完成。当前`PRODUCTION_WRITES=NONE`、`AUTO_SWITCH=OFF`、`APP_BUSINESS=UNKNOWN`，**无需用户购买VPS或重建订阅转换**。
