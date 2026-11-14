# OpenClash 更新提交点与 Mihomo 实际运行身份能力审计（2026-11-14）

> 状态：**上游源码证据 + 候选离线代码/CI PASS + 小型匿名实机版本探针待执行**。没有将任何hook安装到路由器；不存在正式设备更新事件或完整运行参数的新增回执。

## 本轮可验收目标

1. [x] 用固定上游提交与Git blob校验源，确定 OpenClash 自带订阅更新的实际成功/无变化/失败代码路径和有风险的提交位置，不以模糊搜索结果或UI提示充当已验证设备代码。
2. [x] 形成拒绝未确认版本的后置提交观察器**离线契约**及失败/半写/回滚/无变化测试；不生成会自动安装的更新器补丁。
3. [x] 以固定提交在候选分支提供一次新的小型匿名只读设备预检，取得**设备实际安装的**脚本Git blob SHA以及可用的Linux AT_CLKTCK。已完成CI合成/无路由环境安全阻断测试；**尚未在用户iStoreOS上运行**。
4. [x] 核实官方 Mihomo 只读 API：/configs是基本运行设置，/proxies返回代理名称、类型、选中、延迟和历史等元信息；均没有提供所有协议的完整服务器密码/TLS/传输参数。不能依据58/58名称匹配解锁完整运行身份。
5. [ ] 设备已安装更新器字节指纹、可信下载/验证/落盘事件、正式Mihomo完整连接身份及实际业务回执仍缺；任何AI自动资格继承和切线继续禁用。

## 上游证据（与设备安装版本**必须**分开）

- 上游 OpenClash 固定提交 [588cec56111c6f54a1ae24a4b848afbecc1a2f7f](https://github.com/vernesong/OpenClash/commit/588cec56111c6f54a1ae24a4b848afbecc1a2f7f)，文件 [openclash.sh](https://github.com/vernesong/OpenClash/blob/588cec56111c6f54a1ae24a4b848afbecc1a2f7f/luci-app-openclash/root/usr/share/openclash/openclash.sh)，**Git blob SHA** `6c181265ca96c452660653d60ec552d58eccc12c`，GitHub直接取源已核对。
- 在 `config_su_check()` 的已有文件和初次创建两个分支都存在 `mv "$CFG_FILE" "$CONFIG_FILE" 2>/dev/null`，随后**不检查mv返回值**就 `LOG_OUT "...Update Successful!"`；因此仅这条日志不证明目标文件已完成写入。另有 `cmp`相等即`No Change, Do Nothing!`，也有外层`DOWNLOAD_RESULT=2`的无变化分支，需要严格区分它们与有效新提交。
- 最后还调用 `dec_job_counter_and_restart "$restart"`，但是该调用及进程PID后启动都不能作为所有连接参数进入内存的独立摘要。
- 上游脚本在部分下载日志分支直接包含订阅URL或自定义头；**禁止拷贝原始日志到公开Git、Actions或聊天**。私人源SHA/运行ID只能受保护保存在设备内，不发布。
- 用户11月13日23:52的已通过设备回执仍只有 `EXPECTED=58 PRESENT=58 EXTRA_LEAF=1`，`getconf`缺失，及运行中认证API目录。**从未对用户当前安装的`openclash.sh`计算过SHA；不能声称它与以上上游固定版本相同。**

## API 实际能力界限

- Mihomo官方 [API说明](https://wiki.metacubex.one/en/api/)和 [Meta分支路由源](https://github.com/MetaCubeX/mihomo/blob/Meta/hub/route/proxies.go)：`GET /proxies`列出代理名称/类型及相关运行元数据，`GET /configs`是基本运行配置而非协议机密的全量导出；另`PUT /configs`会实际重载、`PUT /proxies/{name}`会改所选线路，**绝不能作为只读证据请求**。
- 设计上未来只有两个明示的不同等级：**操作性冷启动/文件及业务佐证候选**（可以服务人工维护审查）与**完整运行连接身份独立证明**（原高标准）；当前均没有实机通过。不能用前者悄悄替代后者，也不能由用户输入布尔值假装已安装真实观察器。

## 新候选代码、回归与唯一安全预检

- `scripts/ai_openclash_updater_contract.py`：纯离线，精确计算Git blob SHA，严格版本锁，识别两个未经确认的move分支；只有由**未来被确认的设备内受保护观察器**生成下载校验、转换后的YAML校验、受控锁和预备备份、预/后SHA一致、移动返回码0、读取最终文件完成、更新批次/boot-id等真证据，才产生`POSTCOMMIT_OBSERVER_CONTRACT_CANDIDATE_ONLY`。无变化分支只返回`HOLD_NO_NEW_COMMIT_SEPARATE_NO_CHANGE_PROOF`，不能伪造发生过文件替换。任何候选**始终`allow_reconcile=false, allow_switch=false`**。
- `tests/test_ai_openclash_updater_contract.py`：版本漂移、缺失结构、失败下载/校验/落盘、摘要不同、无锁/备份、无变化、错误运行标识及不泄露私人身份的合成测试。
- `scripts/ai_installed_updater_preflight_readonly.sh`：设备上**只读**读取标准已安装更新脚本，使用`wc`+`sha1sum`计算Git blob指纹，并从`/proc/self/auxv`用Ruby core读取`AT_CLKTCK`（若不可读则`UNAVAILABLE`），输出固定状态码、一个公共代码指纹及可能的内核tick频率。没有curl/wget/订阅触发、无配置写入/服务重启/PUT、无打印更新脚本源码及节点详情。和前一次22:46/23:52的只读目录探针不同，**不得重新执行旧探针**。
- 固定候选代码与CI工作流提交 [bf7b1d077a56ee5d3a77ee9364ed155b0bc0fe1e](https://github.com/Kimbersy/openclash/commit/bf7b1d077a56ee5d3a77ee9364ed155b0bc0fe1e)；[GitHub Actions #43467591688](https://github.com/Kimbersy/openclash/actions/runs/43467591688) `completed/success`，包含新postcommit合成安全测试、短Shell与内嵌Ruby语法/无路由安全阻断、旧内核时钟/因果、三AI稳态、三端/非AI回归。
- **部署阶段前置门槛**：先获得iStoreOS实际更新脚本指纹并和该候选定位一致；然后**另行**受控设计hook：以该版本完整原件的备份/校验、候选差异审查、保护运行ID、原子持久事件、意外中断/重复更新恢复、禁泄密、失败回滚、不中断现行订阅及路由等作为交付检查。没有实际安装/回滚授权及新回执前，任何来源hook不得上线。部分内嵌Ruby库在iStoreOS精简系统不可用，最终实现优先可实机验证的Ruby core/Shell能力，不假设Python3已安装。

## 唯一下一步

**用户仅在方便时执行一次本轮新的[只读短预检](../scripts/ai_installed_updater_preflight_readonly.sh)，回传`INSTALLED_UPDATER`与`KERNEL_AT_CLKTCK`的匿名状态行**。根据真实安装版本再确定OpenClash后置事件观察器的安全落点；若版本与pin不一致先重新审计，而不是直接对设备打上游补丁。**完整运行身份仍不能由常规API证明**；在完成可信事件和真实业务验收前，不部署AI自动切换、不改三端或Worker、不买VPS。
