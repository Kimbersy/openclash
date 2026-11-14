# 2026-11-14 22:57之后：自然订阅更新低资源被动观察器候选（未部署）

## 当前已知实机结果，全部直接沿用

- [22:57真实UCI回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_UCI_SUBSCRIPTION_PASS_RECEIPT_20261114_2257.md)：1个`config_subscribe`节，明确启用1，地址已设置，启用日更，未归属桶0，非订阅40桶正确排除。**不是远程更新成功回执**。
- 22:29选中源与正式运行配置文件58/58全部连接字段一致；22:20正式Mihomo IPv4本地`GET /proxies`预期58/58名字存在、内置`PASS-RULE`识别；21:09正式Mihomo规则Provider20/20正数登记。**均不重复**。
- 更早[候选`scripts/ai_openclash_updater_contract.py`](../scripts/ai_openclash_updater_contract.py)已经保存**2026-11-14 07:51实机安装的更新脚本**Git blob `ac6640de36be1cf7dc11ae73796a89078269542c`，匹配官方上游固定提交`813a60a21fba2ec34c3a42f7fdc3d71b47694d25`；该证据只固定**当时**安装文件，不能据此假设后续OpenClash更新没有导致版本变化。上次“安装脚本从未核验”的笼统描述不准确，现纠正为“历史固定版本已核验，未来实际安装/授权时仍需核对变化”。
- 已知上游这版的`Update Successful!`提示存在未校验`mv`返回的风险，且日志成功不等于Mihomo完整内存连接身份已加载。[事件审查与可信证据边界](AI_REFRESH_PROVENANCE_REALITY_20261114.md)，既有`ai_refresh_event_gate.py`、`ai_refresh_causal_sequence.py`、`ai_openclash_updater_contract.py`均已提供严守门禁，继续复用而非重造。

## 本轮实质工程交付

1. [固定源码Git `881b19b5f794b5a7509118289c353393e094a7b1`](https://github.com/Kimbersy/openclash/blob/881b19b5f794b5a7509118289c353393e094a7b1/scripts/ai_refresh_passive_observer_candidate.rb)：**长时观察器候选，绝不直接交给用户运行，也未安装**。只使用Ruby核心与当前已有`uci`接口，读取当前UCI选中源文件、唯一正式Mihomo PID/NetNS/starttime、源/运行配置磁盘文件稳定metadata、`/tmp/openclash.log`的**最多128KiB新增字节**；不打印原日志、文件路径、节点名、机场URL/认证或敏感字段，不调用Controller/API、没有机场下载/刷新/核心重载/策略组PUT。即使源+核心文件+正式进程启动代都在一段日志提示后改变并连续观测稳定，最多输出`PASSIVE_POSTUPDATE_CHRONOLOGY_CANDIDATE_ONLY`，**`TRUSTED_REMOTE_COMMIT=NOT_VERIFIED MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED ALLOW_RECONCILE=NO ALLOW_SWITCH=NO`**。没有原真实下载/校验/提交钩子时不可能凭被动日志自动拿到可信提交，故这是**候选时间线**，不是已实现可信更新事件。
2. 资源/生命周期：默认不启动（`HOLD_NOT_ARMED`）；必须显式指定`--observe <最长秒数> <轮询秒数>`才可能运行，最长24小时、轮询间隔30–900秒且总窗口至少3轮；单实例靠专用`/tmp`的0600无符号链接`flock`，保留锁文件路径防unlink竞态；进程信号TERM/INT停止、退出自动释放锁；不注册cron/procd、未修改启动项，程序本身不创建后台进程。文件只读stat，日志有增量与体积限额，轮转/间隙/重启/不同步均保守HOLD。**/tmp唯一可能新建的文件是私有锁，不是生产配置写入。**
3. [同固定Git的一次性核心环境预检](https://github.com/Kimbersy/openclash/blob/881b19b5f794b5a7509118289c353393e094a7b1/scripts/ai_refresh_observer_runtime_preflight_readonly.rb)：0个`require`，不启动观察器、不读机场/更新日志，只检查`File::NOFOLLOW`、0600私有`flock`互斥、`CLOCK_MONOTONIC`与TERM trap是否在**真实iStoreOS Ruby**可运行，且不改变生产配置/代理。它只在`/tmp`创建一个私有小锁文件；检查完自动释放，不需要清理OpenClash。
4. [完整GitHub CI #43610396691](https://github.com/Kimbersy/openclash/actions/runs/43610396691) `completed/success`：模拟自然更新前后、日志伪成功/失败、源或运行文件单边改动、boot变化、稳定性不足、日志gap/轮转、恶意节点别名不泄露、同一锁第二进程拒绝、默认未武装、运行预算限制与停止逻辑，iStoreOS依赖合同、原P0/三端/非AI与原生Mihomo合成测试全部成功。
5. **路由器准入强制分层**：`tests/test_istoreos_runtime_contract.py`明确仅准许一次性预检脚本进入实机验收；长时观察器仍在`DEVICE_BLOCKED_PENDING_DEPENDENCY_CHECK`，原因是单调时钟、`File::NOFOLLOW`、`flock`与信号trap在用户精简Ruby中的实际可用性尚无直接实机回执。不能凭Ubuntu CI提升为“设备已部署”。

## 当前唯一下一步：先用一次固定SHA的**单次环境兼容性只读预检**

只有准备进行实际自然更新观察前才需要这条；它不是重复58节点/UCI/规则检查。可在iStoreOS TTYD只执行**一次**（外层下载公开固定SHA文件，只走IPv4；内层不联网），回传匿名`RUBY_*`及`PASSIVE_RUNTIME_PREFLIGHT_RESULT`截图即可：

```sh
( umask 077; f="$(mktemp /tmp/ai_obsprim_XXXXXX)" || exit 1; if curl -4 -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/881b19b5f794b5a7509118289c353393e094a7b1/scripts/ai_refresh_observer_runtime_preflight_readonly.rb"; then ruby "$f" || echo "PASSIVE_RUNTIME_PREFLIGHT_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "PASSIVE_RUNTIME_PREFLIGHT_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

若预检PASS，仅证明**Ruby核心机制存在**，绝不认为观察器已安装、订阅更新已成功、核心内存凭据已验，也不自动放行长时观察器；工程端还须在正式监测前复核当地OpenClash安装提交、日志窗口与唯一核心版本，并决定受控有限窗口和终止回滚方案。如果需要植入真正可认证下载/提交事件钩子：必须先备份+兼容核验+回滚、取得用户明确授权；本轮完全未触碰updater。继续持守**全量节点、三AI独立真实业务、真实IPv4地区、动态增量与稳态AI-only备援**的P0，不会缩成3条永久候选。VPS HOLD，三端与非AI不变。
