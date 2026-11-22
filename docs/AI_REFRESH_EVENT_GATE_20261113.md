# AI-only 订阅成功到 Mihomo 运行生效：双证据安全门（2026-11-13，未部署）

> 当前用户截图：iStoreOS `SCHEDULE_AUTO_UPDATE=ENABLED MODE=APPOINTMENT CADENCE=DAILY`；源与活动核心配置磁盘`SOURCE_RUNTIME_DISK_DEFINITIONS=MATCH`，但`REMOTE_UPDATE_SUCCESS=UNVERIFIED`、`Mihomo_RELOAD_CONFIRMED=NO`、`AI_MONITOR_INSTALLED=NO`。探针已真实运行完毕，**`NO`表示没有取得运行内存重载证据，不代表发生重载失败**。不需要再重复这一探针。

## 已核对上游（不等于当前iStoreOS安装版本字节完全相同）

- OpenClash 上游 UI `config-subscribe.lua` 的 `auto_update=1`、`config_auto_update_mode=0`、`config_update_week_time=*`对应启用定时每天更新。用户实机与此配置模式相符。上游：https://github.com/vernesong/OpenClash/blob/master/luci-app-openclash/luasrc/model/cbi/openclash/config-subscribe.lua。
- 上游`/usr/share/openclash/openclash.sh`订阅工作流中有`Config File〖...〗Update Successful!` / `No Change, Do Nothing!` / `Update Error`等日志提示，且成功后还需要服务重载；**提示本身不能证明下载后真正入内存，也不能代替可信绑定到本次订阅快照的成功事件**。`Config File Update Successful!`的上游实现靠近`mv`，不能以文本包含匹配作为唯一强凭据。上游：https://github.com/vernesong/OpenClash/blob/master/luci-app-openclash/root/usr/share/openclash/openclash.sh。
- 上游曾有更新界面只表明请求启动、不能确认下载/校验/写盘最终成败的问题：https://github.com/vernesong/OpenClash/issues/5239（2026-07-16）。因此 **UI更新成功 / HTTP接口启动返回 / 磁盘文件mTime**都不能单独作为调度资格变更授权。

## 离线纯函数安全门

- [`scripts/ai_refresh_event_gate.py`](../scripts/ai_refresh_event_gate.py)：不访问任何网络或磁盘、不写Mihomo控制API、不修改配置；审查一个已验证的**私有节点manifest**和两份由未来可信本地观察器生成的**结构化事件**。直接传入来源不明的JSON/字符串或允许客户端自行设置`validated_download=True`不构成可信证据。
- 第一证：OpenClash订阅事件来自经过验证的成功更新钩子，明确区分`VALIDATED_CHANGED`与**确有下载校验依据**的`VALIDATED_NO_CHANGE`，需记录与本次订阅快照完整SHA256相符的`run_id`、结束时间、下载校验和commit完成信号。普通日志或界面动作不构成第一证。
- 第二证：当前Mihomo核心是同一批次，**独立且带鉴权**读取运行时实际节点/Provider信息，解析全部生效节点的完整连接身份，正规化为`{node_name: SHA256(canonical_node_definition)}`列表的有序摘要；并核对所有当前Provider已加载。只见磁盘配置一致/唯一运行PID/普通`GET /proxies`名称列表不等于完整节点参数和内存重载证明；若受限于运行API无法核验完整参数，则保持`HOLD_NO_REFRESH_PROOF`，不得伪造成功事件。
- 两份事件必须同一批次、时间先后合理且在有效期内：运行快照的规范节点身份摘要与私有manifest一致，源snapshot独立核对原始订阅字节摘要。**原始YAML的SHA256与运行时重写后的YAML不能直接相等比较**；因此对后者采用规范节点定义摘要。源覆盖不足、更新失败、未认证核心、旧事件、无Provider/节点身份的各种分支均不允许向下晋级。
- 通过后输出仅`VERIFIED_SNAPSHOT_READY`, `allow_reconcile=True`, `allow_switch=False`，只授权增量私有节点资格记录合并；**它绝不赋予AI真实业务资格、配置发布、自动选线、修改非AI组的权限**。上游观察器尚未实现或在用户路由器安装，这是一道离线安全门而不是实机重载验收。

## 代码/测试/上线边界

- 固定可复现版本：参见当前分支对应包含`ai_refresh_event_gate.py`和`tests/test_ai_refresh_event_gate.py`的固定Git提交（由GitHub CI和home-it-index任务记录单独固定），模拟10+类通过/阻止路径。
- 三端保持同一套公共订阅转换；不修改`main/Clash-Li.ini`、`main/list/AI.list`、Android YAML或Shadowrocket配置；AI-only候选生成器和普通网站/Disney/GitHub/Telegram等非AI回归继续保留。
- **唯一下一步**：只读核验当前iStoreOS上已安装的OpenClash订阅更新脚本的实际版本/事件状态，以及运行核心可提供的独立已加载节点身份资料；如必须使用控制API，则先只读审查绑定地址和鉴权方式且不展示token。随后实现本机可信事件适配器+私有状态文件、原子更新和停止/回滚生命周期；**先DRY_RUN再审批自动控制AI-only组**。未证实的运行核心不可触发自动资格重建。
