# 2026-11-14 22:29 现行源/核心58条完整定义一致之后：启用订阅来源UCI元数据只读门禁

## 复用的固定真实回执

1. [22:29用户真实设备回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_FULL_DEFINITIONS_PASS_RECEIPT_20261114_2229.md)：`SOURCE_RUNTIME_DISK_FULL_DEFINITIONS_MATCH`，源/当前正式核心配置文件各58条、名字交集58、完整Hash定义匹配58、同名参数差异0、两侧独有0；这只证明**两份磁盘配置定义相同**，不证明Mihomo内存连接凭据或全部原机场订阅来源身份。
2. [22:20用户真实设备API回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_RUNTIME_LEAF_NAME_PASS_RECEIPT_20261114_2220.md)：正式核心IPv4环回`GET /proxies`，58/58预期节点名字存在、缺失0、未知额外0，内置`PASS-RULE`1项归类；21:09实机20/20规则Provider正数登记PASS继续保留。**不得重复既有配置、节点名字、规则、缓存/Geo/socket检查**。
3. 上游OpenClash [config-subscribe.lua](https://github.com/vernesong/OpenClash/blob/master/luci-app-openclash/luasrc/model/cbi/openclash/config-subscribe.lua)使用`config_subscribe`源节、`enabled`标志以及`auto_update`/更新模式等选项。UI可能将缺少`enabled`值展示为默认启用，因此仅凭UCI显示中该项缺省**不得宣称已显式启用或禁用**，需输出`UNKNOWN`交后续真实状态查证。

## 候选工程、风险边界与回归

- 固定[Git源码 `31d9611d49877ebe9c3689000b8bbbb1834ed99a`](https://github.com/Kimbersy/openclash/blob/31d9611d49877ebe9c3689000b8bbbb1834ed99a/scripts/ai_active_subscriptions_metadata_readonly.rb)，独立单文件Ruby，不需要`require`任何额外Ruby库，仅通过本机`uci -q show openclash`读取现有UCI字符串。**不访问Controller/API，不下载或刷新原机场订阅，不改配置/路由，不启Listener、自动切线**。
- 只解析`config_subscribe`匿名或具名section、`enabled`/`enable`标志、仅“是否有address”（不保存或打印URL正文）、`config.config_path`是否已设、`auto_update`与更新间隔类别。输出匿名计数：`UCI_SUBSCRIPTION_SECTION_COUNT`、`UCI_EXPLICIT_ENABLED_COUNT`、`UCI_EXPLICIT_DISABLED_COUNT`、`UCI_ENABLE_FLAG_UNKNOWN_COUNT`、`UCI_ENABLE_FLAG_CONFLICT_COUNT`、`UCI_ENABLED_ADDRESS_MISSING_COUNT`、`UCI_ORPHAN_OPTION_BUCKETS`、`UCI_SELECTED_CONFIG_DECLARED`、`UCI_AUTO_UPDATE`、`UCI_UPDATE_CADENCE`。不打印订阅URL、alias/节点名、账号密钥或整段UCI信息。
- 源存在但启用状态缺省、冲突/无明确定义、订阅地址缺失、没有源节均保守`HOLD`，**不是已经证明所有源没有订阅内容**。若`UCI_ENABLED_SOURCE_METADATA_CLASSIFIED`，仅证“UCI选项可以按显式标志统计”，并明确`ENABLED_SUBSCRIPTION_MERGE_PROVENANCE=NOT_VERIFIED REMOTE_SUBSCRIPTION_REFRESH_SUCCESS=NOT_VERIFIED MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED AI_BUSINESS=UNKNOWN`。定时计划存在≠执行成功；实际合并来源、每条完整身份仍需独立可信证据。外层下载`curl -4`若临时TLS失败，记录`HOLD_DOWNLOAD_UNAVAILABLE`，不借此改IPv6/路由。
- [完整GitHub CI #43605761159](https://github.com/Kimbersy/openclash/actions/runs/43605761159) `completed/success`：具名/匿名UCI订阅节、显式启用/禁用/未知、缺地址、冲突、孤儿项、APPOINTMENT每日/每周及LOOP周期、无敏感输出/无HTTP、Router精简Ruby依赖、既有全部P0/三端/非AI回归通过。**仅代码验收，新工具尚未实机运行**。

## 唯一下一步：一次已固定SHA的本地UCI匿名来源状态回执

在家里 iStoreOS TTYD **执行下面唯一一条**（外层公开固定SHA程序仅以IPv4下载到`/tmp`，程序自身仅查询设备本地UCI元数据）：

```sh
( umask 077; f="$(mktemp /tmp/ai_subuci_XXXXXX)" || exit 1; if curl -4 -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/31d9611d49877ebe9c3689000b8bbbb1834ed99a/scripts/ai_active_subscriptions_metadata_readonly.rb"; then ruby "$f" || echo "SUBSCRIPTION_METADATA_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "SUBSCRIPTION_METADATA_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

只回传`SUBSCRIPTION_METADATA_RESULT`及匿名`UCI_*`行（截图即可）。如果HOLD，仅依据状态决定后续源码/证据，不改实际来源/更新计划。若明确启用来源数量确定，继续结合OpenClash原更新/合并/重载回执推进逐源真实性与动态增量，再做ChatGPT/Gemini/NotebookLM真实业务资格和IPv4出口国家、稳态备援，不重复已成功的58节点/规则检查。VPS仍HOLD，现有生产网络不变。
