# 2026-11-14 21:40 叶节点GET后Controller归属瞬时HOLD：修订版与实机门禁

## 历史事实（保留不重复）

- [21:40 iStoreOS实机原始回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_LEAF_OWNER_HOLD_RECEIPT_20261114_2140.md)：用户执行固定[Git `7932c0b7ca7e7288e36ed4e824baf40b1e0fe1d7`](https://github.com/Kimbersy/openclash/commit/7932c0b7ca7e7288e36ed4e824baf40b1e0fe1d7)的`GET /proxies`只读清点，输出`LEAF_INVENTORY_RESULT=HOLD_CONTROLLER_OWNER_CHANGED`，没有任何有效节点总数可用于验收。旧脚本确实进入`api_read`尝试，但**不能判断GET是否成功，返回数据被安全丢弃**；绝不能因此声称Mihomo重启、IP变更或节点丢失。
- [21:09正式Mihomo真实规则Provider API通过](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_LIVE_RULE_PROVIDER_PASS_20261114_2109.md)：IPv4环回`GET /providers/rules`成功，全部20/20规则Provider登记且报告正数`ruleCount`，这是**规则集**不是机场节点数。20:54已证PID/NetNS与IPv6 wildcard监听inode归属，底层双栈socket并非要求用户启用IPv6出口。此前Geo、缓存、MRS、合成语法验收不重复。

## 修复的具体代码风险与强保守约束

旧版`core_fd_sockets(pid)`遍历`/proc/PID/fd/*`，任意一个fd在列目录和`readlink`之间瞬时消失都会被最外层`rescue StandardError`判为全局归属未知。因为在本机`GET /proxies`前后各采集一次监听归属，API连接阶段的临时fd可能被回收，从而触发`HOLD_CONTROLLER_OWNER_CHANGED`；这是**已识别的可复现代码竞态假设**，不是实机根因已证明。

- 固定新源码：[Git `856dccce2e938c63747bd81052391423b179067b`](https://github.com/Kimbersy/openclash/commit/856dccce2e938c63747bd81052391423b179067b)中的单文件 [`scripts/ai_runtime_leaf_inventory_readonly.rb`](https://github.com/Kimbersy/openclash/blob/856dccce2e938c63747bd81052391423b179067b/scripts/ai_runtime_leaf_inventory_readonly.rb)。针对`/proc`FD临时消失，只对`Errno::ENOENT`/`Errno::EBADF`的临时FD读取失败跳过；只以同端口**真实LISTEN socket inode**在正式Mihomo持有的FD中出现作为归属证明。若真实监听FD不在，仍严格`HOLD`。对EACCES/其它异常和格式不明保持保守阻断。
- **强化核心进程身份**：GET前后比较正式进程可执行文件真实路径、网络命名空间以及`/proc/PID/stat`的Linux字段22启动时钟，不允许PID复用或进程替换在相同PID/端口下伪造同一核心。监听socket绑定类别和inode必须前后完全一致；发生真实变化即`HOLD_CONTROLLER_OWNER_CHANGED`，重核读不到即独立`HOLD_CONTROLLER_OWNER_RECHECK_UNAVAILABLE`，身份变化则`HOLD_CORE_PROCESS_CHANGED`，从而不再混淆三种情况。
- **IPv4优先硬性维持**：外层固定脚本下载curl`-4`，内层对已验证正式Controller仅`--ipv4 --noproxy '*'`访问`http://127.0.0.1:PORT/proxies`，只GET，不用IPv6 fallback。Bearer密钥只在路由器进程内内存与curl stdin流转，不在argv/日志/终端中出现。不调用Mihomo新进程、PUT/刷新/切组、改配置、Worker或三端订阅。
- 响应上限3MB，连接限2秒、整体7秒，匿名输出`LEAF_INVENTORY_RESULT`、当前正式配置的内嵌叶节点数量、API叶节点名字覆盖/缺失/额外与意外组数量。可接受的唯一PASS是`LIVE_LEAF_NAME_COVERAGE_PASS`，且严格声明`LIVE_FULL_CONNECTION_FINGERPRINTS=NOT_VERIFIED ENABLED_SUBSCRIPTION_SOURCE_COVERAGE=NOT_VERIFIED`；当前节点完整连接参数与业务资格仍必须独立证明。
- [完整GitHub CI #43601488777](https://github.com/Kimbersy/openclash/actions/runs/43601488777) `completed/success`，包含瞬时无关FD关闭容忍、真正监听socket消失或inode替换仍阻断、其它FD权限错误HOLD、PID/stat字段22验证、既有58/74等动态节点及未知组、精简Ruby仅`psych`依赖、原P0/三端/非AI/合成原生Mihomo全套回归。**这不是家中新版已运行的实机证据。**

## 唯一下一步（一条新的固定SHA IPv4-only 只读命令）

在家里 iStoreOS TTYD **只运行一次**，本次仍需真实取得`GET /proxies`叶节点匿名计数。外层只用IPv4取得公开固定单文件至`/tmp`；Ruby程序本身只向已确认归属的本机Controller只读GET，不存储私人节点清单。

```sh
( umask 077; f="$(mktemp /tmp/ai_leafrace_XXXXXX)" || exit 1; if curl -4 -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/856dccce2e938c63747bd81052391423b179067b/scripts/ai_runtime_leaf_inventory_readonly.rb"; then ruby "$f" || echo "LEAF_INVENTORY_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "LEAF_INVENTORY_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

只回传截图或`LEAF_INVENTORY_RESULT`、`CONFIG_EMBEDDED_LEAF_COUNT`、`API_EXPECTED_LEAF_PRESENT/MISSING`等匿名结果即可。若HOLD，**不重复旧`7932c0b7`、规则Provider、socket或任何Geo/MRS/缓存探针**，也不修改Controller/IPv6；按具体HOLD码继续工程修复。

后续P0：与真实启用订阅的所有叶节点完整指纹/内存加载一致、ChatGPT/Gemini/NotebookLM三平台各自真实账号业务、可信双源IPv4国家、原订阅真实成功更新后的增量维护、AI-only防抖主备与人工地区锁；当前`BUSINESS=UNKNOWN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`，VPS HOLD。
