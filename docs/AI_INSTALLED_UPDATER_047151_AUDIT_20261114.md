# 2026-11-14 07:51 iStoreOS 安装更新脚本精确版本确认与离线风险审计

## 目标与验收

- 用户设备固定回执：`INSTALLED_UPDATER=DIFFERENT_VERSION GIT_BLOB_SHA=ac6640de36be1cf7dc11ae73796a89078269542c`，`UPDATER_FINGERPRINT=FINISHED PRODUCTION_WRITES=NONE`；此为 `/usr/share/openclash/openclash.sh` 的 Git blob 指纹，**不是整个OpenClash包的安装版本号**。
- 在官方 `vernesong/OpenClash` 的指定路径历史中，文件SHA精确命中 [commit 813a60a21fba2ec34c3a42f7fdc3d71b47694d25](https://github.com/vernesong/OpenClash/commit/813a60a21fba2ec34c3a42f7fdc3d71b47694d25)，提交日期2026-08-03，提交主题`0.47.151`。该提交下的 [openclash.sh](https://github.com/vernesong/OpenClash/blob/813a60a21fba2ec34c3a42f7fdc3d71b47694d25/luci-app-openclash/root/usr/share/openclash/openclash.sh) 的Git blob亦为`ac6640de36be1cf7dc11ae73796a89078269542c`。**不因文件碰巧完全一致就假定所有组件都在0.47.151。**
- 由用户7:43实机读到`AT_CLKTCK=100`（非猜测），以及11月13日23:52的`EXPECTED=58 PRESENT=58 EXTRA_LEAF=1`仍保留，不重复检测；这不等于下载/完整内存已被认证。

## 本版已审计的代码入口和差异

1. `config_download()`调用 `DOWNLOAD_FILE_CURL` 后捕获 `DOWNLOAD_RESULT=$?`；其中`DOWNLOAD_RESULT=2`属于`No Change`分支，不是新提交。下载校验和Mihomo配置测试是独立阶段，不能把HTTP请求成功直接当成落盘。
2. `config_su_check()` 在`cmp`不相等及首次创建两条路径均执行 `mv "$CFG_FILE" "$CONFIG_FILE" 2>/dev/null`，但紧跟的 `LOG_OUT "...Update Successful!"` **没有校验该`mv`的退出码和实际目标内容**。这是操作成功审计的缺口；日志本身不足以证明订阅落盘成功。
3. 0.47.151 的 `config_error()`只输出错误并删除临时文件，没有后来版本中的显式`exit_code=1`标记；该`openclash.sh`结尾只有 `dec_job_counter_and_restart "$restart"` 和`del_lock`，没有后来版本的显式`exit "$exit_code"`。因此不能套用10月版的错误传播语义；也不能只检查最终脚本shell返回状态便宣称下载成功。
4. 活动源的`CONFIG_FILE == CONFIG_PATH`时设置`restart=1`，具体重启由外部函数`dec_job_counter_and_restart`完成。目录一致、此标志或更新日志均不能替代唯一正式核心确实加载对应完整节点参数的证明。
5. 上游日志/脚本可能含订阅URL/自定义请求头的输出，原始日志、源YAML及账号/节点密码不得存公开Git或聊天。只允许匿名阶段码/公开上游**代码**哈希。

## 本轮候选源码更改（仅离线）

- `scripts/ai_openclash_updater_contract.py` 新增固定真实设备脚本常量`KNOWN_DEVICE_UPDATER_BLOB_SHA`和`KNOWN_DEVICE_UPDATER_COMMIT`，`audit_installed_device_updater`只认可固定Git对象和0.47.151的特定结构：双`mv`未校验、双成功日志、无显式错误exit_code和最终exit代码、当前活动源重启标记；不把10月版当作适用的设备patch。无论模拟测试通过与否，始终`can_instrument=false`、`allow_reconcile=false`、`allow_switch=false`。
- `tests/test_ai_openclash_updater_contract.py` 增加实际设备blob pin与上游commit的显式对照、模拟0.47.151结构、版本漂移、非法额外退出状态及非可安装结果的回归。完整上游源来自官方固定Git提交，并未将真实源YAML或私有配置放入fixture。
- 固定代码/合成回归提交 [4bbf924ae8f919cf6c1a607f9c90416308377af9](https://github.com/Kimbersy/openclash/commit/4bbf924ae8f919cf6c1a607f9c90416308377af9)，[GitHub Actions #43530779544](https://github.com/Kimbersy/openclash/actions/runs/43530779544) `completed/success`。原有AI业务资格/防抖/三端/非AI回归仍跑过。**CI并非设备安装或自然订阅成功的回执**。

## 本轮安全与发布状态

- 设备实际安装脚本已完成**身份定位**，旧10月上游版本`6c181265...`不应套用；当前没有更新器hook、cron新任务、AI监控或自动切换部署，也没修改OpenClash/Worker/KV/流媒体/三端。
- 仍未验收远端机场订阅下载/最终写盘、Mihomo完整运行连接身份、ChatGPT/Gemini/NotebookLM真实业务和稳态接替。
- 未经用户认可的安装+回滚方案，不得对`/usr/share/openclash/openclash.sh`直接修改、安装后置hook或重启服务。

## 唯一下一步

**代码侧**专门针对已经固定的0.47.151更新路径设计可撤销的最小postcommit观察器候选与离线故障注入测试：覆盖下载失败、转换/YAML校验失败、`mv`返回错误、读取目标文件摘要失败、无变化、同一批次并发、重启/掉电中断、恢复、回滚。明确升级后不能自动沿用字节pin；订阅成功/完整内存认证之前保持`HOLD_UPDATE_EVIDENCE`且不选线。**不再让用户重复07:51版本检测，也不安装任何hook。**
