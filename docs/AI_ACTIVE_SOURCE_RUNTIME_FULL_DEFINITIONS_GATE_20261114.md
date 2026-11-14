# 2026-11-14 22:20 运行态叶节点名字全覆盖后：选中源 vs 正式核心文件完整定义只读门禁

## 复用已确认的实机证据

- [22:20 用户真实iStoreOS回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_RUNTIME_LEAF_NAME_PASS_RECEIPT_20261114_2220.md)：固定Git `cf3c1ff9`的本机IPv4-only `GET /proxies`通过，配置58嵌入叶、proxy-provider 0、API预期匹配58/58、缺失0、额外不可信0、无未知组，7项已验证内置对象中`PASS-RULE` 1；`LIVE_LEAF_NAME_COVERAGE_PASS`。不能把这7项内置算成机场节点。
- 21:09正式Mihomo`GET /providers/rules`显示20份规则Provider正数条目；20:54已确认Controller双栈监听可由IPv4 `127.0.0.1`访问。此前19:22磁盘MRS头HOLD独立保留；规则/Geo/缓存/NetNS等不再重跑。
- 当前仍明确`LIVE_FULL_CONNECTION_FINGERPRINTS=NOT_VERIFIED ENABLED_SUBSCRIPTION_SOURCE_COVERAGE=NOT_VERIFIED AI_BUSINESS=UNKNOWN`；无任何业务资格、远程刷新成功、实测IPv4出口国家可凭名字通过。

## 本轮工程：有限但有价值的完整连接定义比较

- 固定[源码Git `060ccb0cee15fbe8a1ff670a052108c2cff70dc9`](https://github.com/Kimbersy/openclash/blob/060ccb0cee15fbe8a1ff670a052108c2cff70dc9/scripts/ai_source_runtime_definitions_readonly.rb)，单文件Ruby，只有实机已证`require 'psych'`，以及iStoreOS自带本机`uci -q get openclash.config.config_path`。不要求`timeout/open3/tempfile/uri`、不访问Controller/HTTP、不开第二核心/Listener、不更新/切换任何Provider或策略组。
- 严格只定位唯一正在运行的正式Mihomo PID/核心可执行路径/核心启动时钟与实际`-f/-d`配置，且用`uci`读取**当前选中的OpenClash源配置**路径（文件须留在`/etc/openclash/config/`可信目录）。源/运行文件有大小上限20 MB，读取前后检查dev/ino/size/mtime/ctime；源配置不可定位、布局不认识、含动态`proxy-providers`、进程发生变化即保守`HOLD`。
- 对两份配置内所有内嵌代理按名字建立完整原始Hash映射，逐条比较**全部字段**（服务端、端口、密码/UUID、TLS、SNI、传输选项及所有其它嵌套字段），不会因为条目排序不同误报，但同名换连接参数立即统计为差异。只输出`SOURCE_EMBEDDED_LEAF_COUNT`、`RUNTIME_DISK_LEAF_COUNT`、`COMMON_NAME_COUNT`、`FULL_DEFINITION_MATCH_COUNT`、`SAME_NAME_DIFFERENT_DEFINITION_COUNT`、`SOURCE_ONLY_COUNT`、`RUNTIME_ONLY_COUNT`和仅排序变化的类别；**绝不输出源/运行路径、真实节点名称、服务器、端口、认证、指纹、密钥或原始内容**。
- 若取得`SOURCE_RUNTIME_DISK_FULL_DEFINITIONS_MATCH`，其严格含义是“**当次当前选中源文件与正式核心使用的配置文件之间，58条（或当次动态数量）节点的全部映射值一致**”，结合22:20名字API证据，可提升对更新漂移的信心；但**仍不是Mihomo内存完整参数/认证字节已核验，也不证明OpenClash所有启用订阅源合并成功、最近远程更新成功或ChatGPT/Gemini/NotebookLM业务可用**。
- [完整GitHub CI #43604783545](https://github.com/Kimbersy/openclash/actions/runs/43604783545) `completed/success`：58节点重排、同名改server/port/UUID/TLS/WS均正确HOLD、额外/缺失/重名/动态Provider保护、无HTTP与密钥泄露、iStoreOS精简Ruby准入、原P0/Android/iOS/非AI及合成Mihomo回归全部通过。CI还不是家中新版结果。

## 唯一下一步：一次固定SHA仅本机文件定义检查

用户在iStoreOS TTYD只执行下面这一条固定版本命令一次：外层`curl -4`仅从公开Git仓库下载已验证的单文件程序到`/tmp`，脚本本身没有外网访问，只会读取本地`uci`和两份现有配置并输出匿名聚合。

```sh
( umask 077; f="$(mktemp /tmp/ai_srcdefs_XXXXXX)" || exit 1; if curl -4 -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/060ccb0cee15fbe8a1ff670a052108c2cff70dc9/scripts/ai_source_runtime_definitions_readonly.rb"; then ruby "$f" || echo "SOURCE_RUNTIME_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "SOURCE_RUNTIME_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

回传`SOURCE_RUNTIME_RESULT`以及全部匿名数量即可，截图即可。如果`HOLD_SELECTED_SOURCE_UNAVAILABLE`或`HOLD_SOURCE_RUNTIME_DEFINITION_DIFFERENCE`，记录并由工程端解释是配置路径/合并结果差异，**不修改真实OpenClash配置来凑PASS**，不重新下载源订阅、不触发重载。若单次下载不可达停止，无需旧脚本重跑。

**项目P0仍不可缩水**：所有启用订阅来源的真实完整身份/内存加载凭据、安全逐节点三AI业务资格、双源IPv4出口国家、增量身份继承撤销与无抖动主备、非AI冻结。AI仍`BUSINESS=UNKNOWN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`；VPS继续HOLD。
