# 路由器P0：NotebookLM单核心低能耗入口的**一键只读准入**（2026-11-14 12:21后）

> **最新实质结果**：已创建完全自包含的`scripts/ai_notebook_router_admission_readonly.rb`，只检查当前家用iStoreOS上Mihomo的进程版本、17881 TCP监听占用与**运行配置**能否容纳独立检测入口，所有私有值在本机内存检查，向TTYD只输出匿名状态；**GitHub源码与CI通过，不是用户家中已执行回执**。此前单核心独立listener方案已由官方Mihomo v1.19.34原生`-t`测试通过，但**不能代替用户实机内核版本/端口/配置验证**。

## 交付验收（不偏离P0主线）

- 路由器P0最终仍要求：所有当前启用且生效的机场订阅节点低负载发现与增量筛选；ChatGPT/Gemini/NotebookLM各自全部合格池、按双源实测出口地区自动分组、跟随原订阅实际成功更新、稳态优选与故障接替；非AI/Worker/三端现有转换不变，Android/iOS智能化仅P1；首轮正负各一条只是校准。
- NotebookLM入口点击：用户实测不支持节点即使Google/YouTube可用，也直接`location=unsupported`、不先登录；支持节点进入`?icid=...`及可能的Google登录。短时无登录态`curl`是否能复现两种真实节点点击结果**尚未经过家中正负样本校准**；脚本检测不能冒充业务可用性。
- **本轮最小完成项**：把单核心Loopback listener的离线候选推进到**用户实机零生产写入的只读安全准入**，减少以后多轮无意义询问与手工操作。

## 已实现的只读检查工具

源码固定为[候选Git `13fbc70a79dbd395884977825f5a4d89b1ec4b37`](https://github.com/Kimbersy/openclash/commit/13fbc70a79dbd395884977825f5a4d89b1ec4b37)（独立Ruby单文件），[GitHub Actions #43556800559](https://github.com/Kimbersy/openclash/actions/runs/43556800559) `completed/success`，包括Ruby单文件安全回归、原单核监听器原生Mihomo `-t`、NotebookLM CTA、全地区增量及三端非AI回归。

`scripts/ai_notebook_router_admission_readonly.rb`：
1. **复用既有`ai_live_membership_readonly.rb`验证过的核心定位规则**，直接扫描`/proc`，只接受**唯一**、实际执行文件在`/etc/openclash/core/`下的非临时测试进程；不读取或输出进程argv、私有配置路径、机场信息。
2. 仅对该已装核心运行一次带3秒上限的`-v`，只输出可匹配的`X.Y.Z`版本号；不能识别则`HOLD_CORE_VERSION_UNKNOWN`，不拿OpenClash`0.47.151`更新脚本文件版本冒充Mihomo内核。
3. 只读扫描内核`/proc/net/tcp`和`tcp6`所有现有`LISTEN`条目的端口：`PORT_17881=NOT_LISTENING/IN_USE/UNKNOWN`；一个早期时间点端口空闲**不代表当前仍空闲**。
4. 本机读取**唯一实际Mihomo当前运行的配置路径**，解析Ruby `Psych.safe_load(aliases:false)`，匿名核对原`🤖 AI`为`select`、内嵌叶/组无重名、原listeners与各顶层代理端口未占用17881、没有专用组/入站名冲突；出现未来Provider及源身份尚未完成核实时保持HOLD。**不打印配置内容、节点名、机场地址、服务器、凭据、Controller Secret或任何原始URL。**
5. 输出`ADMISSION=READY_FOR_PRIVATE_COPY_NATIVE_TEST_ONLY`的语义仅是**允许进入受保护配置副本的下一道验证**，不是生产发布/业务通过。`PRIVATE_COPY_TEST=NOT_RUN`、`NODE_BUSINESS=UNKNOWN`、`AUTO_SWITCH=OFF`与`PRODUCTION_WRITES=NONE`始终明确。
6. 额外修正安全表述：专用`select`列表第一个`REJECT`**只是预期默认值**，配置状态持久化可能恢复旧选项，因此代码从`starts_disabled=true`改为`default_reject_configured=true`+`runtime_reject_verified=false`；获准灰度后必须由真实Controller读取专用组当前值确为`REJECT`，否则立刻停止，不得让它被当成已经禁用。

## 可给用户的一条独立只读命令（需在用户授权操作时执行）

以下通过HTTPS下载**固定提交**的**一个Ruby脚本**到`/tmp`临时文件、执行只读检查后删除临时文件；**不改任何正式配置、不改当前AI选择、不调用Controller PUT/网络测速、不重启**。仅本机临时文件创建与删除，不声称绝对“零写盘”。

```sh
( umask 077; f="$(mktemp /tmp/ai_nbr_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/13fbc70a79dbd395884977825f5a4d89b1ec4b37/scripts/ai_notebook_router_admission_readonly.rb"; then ruby "$f"; else echo "ADMISSION=HOLD_DOWNLOAD_UNAVAILABLE PRODUCTION_WRITES=NONE"; fi; rm -f "$f" )
```

这不是远程执行/实时验收；用户未实际运行之前只保留`DEVICE_ADMISSION=UNTESTED`。发生错误时不根据上一个版本的成功状态推断最新结果。用户只需将**不包含私有内容的匿名状态输出**返回，不需要提供完整配置、订阅URL、节点标签或IP。

## 固定当前状态、唯一下一步

- [x] 单核Loopback入口合成生成和官方Mihomo v1.19.34原生`-t`通过（旧[CI #43552254288](https://github.com/Kimbersy/openclash/actions/runs/43552254288)）。
- [x] 独立只读实机准入脚本、单元回归和重新执行整套CI通过（本轮[CI #43556800559](https://github.com/Kimbersy/openclash/actions/runs/43556800559)）。
- [ ] **家中iStoreOS当前版本/端口与运行配置只读准入尚未实际执行**；用户无需重查旧58/58、100Hz、0.47.151脚本文件。
- [ ] 实机当前内核对真实私有副本的`-t`、独立测试组`REJECT`回读、正负节点HTTPS CTA校准、正式三个AI业务资格、订阅后自动更新与真实故障接替均未过，当前不能发布AI自动切线。

**唯一下一步**：取得用户一次性**只读匿名准入回执**（上面固定单脚本命令）。如果`HOLD`，只针对该项差异定位，不要求重复旧检测；如果达到`READY_FOR_PRIVATE_COPY_NATIVE_TEST_ONLY`，下一步才做受保护配置副本的当前核心`-t`与回滚方案，集中说明灰度影响并等用户明确授权，**未获授权不能安装监听/切换任何现网组**。不新增后台任务，不购VPS。
