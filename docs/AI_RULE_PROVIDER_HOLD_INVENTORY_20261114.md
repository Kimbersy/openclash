# 2026-11-14：用户真实 HOLD_RULE_PROVIDERS 后的规则集来源诊断与后续路径

## 一、来自用户真实设备的新回执（不是推断）

用户在iStoreOS TTYD运行固定Git [`43e9ae2`](https://github.com/Kimbersy/openclash/commit/43e9ae2bd0b01d3dfb65e2328803073986290930)的受保护私有副本门禁，完整匿名输出：

```text
PRIVATE_COPY_GATE=START SOURCE_READ_ONLY=YES
PRIVATE_COPY_RESULT=HOLD_RULE_PROVIDERS
PRIVATE_COPY_TEST=NOT_RUN PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AUTO_SWITCH=OFF
```

**已确认**：当前实际在用Mihomo配置包含非空`rule-providers`；这是按安全设计主动暂停，**未生成私有副本、未执行真实配置`-t`、未安装监听、未改变正式配置或节点选择**。不需要重做15:02核心识别/17881未监听/配置结构、15:22三段版本解析、15:46已装内核纯合成Listener原生`-t`。不能因为希望测试成功而删除或略过原有rule-providers。

## 二、为什么要区分来源，而不是直接复制现有配置

[Mihomo官方Rule-Providers说明](https://wiki.metacubex.one/en/config/rule-providers/)支持`type: http`、`type: file`、`type: inline`：HTTP可能要下载缓存（没有显式`path`时可能按URL的MD5生成缓存名）；文件路径受内核`-d` HomeDir/SAFE_PATHS约束；`path-in-bundle`还可能引用BundleMRS.7z。把真实配置直接拷到独立`-d`目录执行`-t`，不能保证规则缓存路径保持有效，更不能保证绝不尝试网络访问。

**本轮方案**：只在用户设备原配置上做**只读的匿名结构及路径元数据清点**，先知道真实依赖类型，再决定是否能采用本地规则缓存的受保护私有副本；保留原配置和所有分流规则。对所有Provider都使用既有更新方式，不改正式Provider地址、缓存或interval。

## 三、完成的源码、回归与未完成工作

- 固定[Git `b5d9ced83925768860f1aa2ada3834c84571f5e2`](https://github.com/Kimbersy/openclash/commit/b5d9ced83925768860f1aa2ada3834c84571f5e2)：新增[`scripts/ai_rule_provider_inventory_readonly.rb`](https://github.com/Kimbersy/openclash/blob/b5d9ced83925768860f1aa2ada3834c84571f5e2/scripts/ai_rule_provider_inventory_readonly.rb)（iStoreOS独立Ruby脚本，仅`require 'psych'`，该依赖已有15:02实际加载凭据）；对应[合成测试](https://github.com/Kimbersy/openclash/blob/b5d9ced83925768860f1aa2ada3834c84571f5e2/tests/test_ai_rule_provider_inventory_readonly.rb)覆盖三种来源、缓存存在/未指定、目录越界/符号链接、Geo/RULE-SET/节点Provider及匿名不泄露。
- [GitHub Actions #43576237705](https://github.com/Kimbersy/openclash/actions/runs/43576237705) `completed/success`：新增规则集只读回归、iStoreOS精简Ruby依赖硬门禁、原全部三AI/地区/订阅增量/非AI零差异及官方Mihomo离线原生`-t`测试全部通过。这仍是**源码CI，不是家中规则集分布的回执**。
- 只读脚本输出规则集总数、HTTP/file/inline/未知类型数量；明确路径属于工作目录且是普通文件的数量、文件不存在或未显式给路径、目录越界/符号链接的数量；规则是否存在RULE-SET/Geo引用、是否存在节点Provider自动引用等。只用文件存在/大小/真实路径元数据判断，**不读取缓存文件内容**、不输出名称、路径、URL、节点信息、账号或完整配置，不创建私有配置副本、不运行Mihomo、没有任何controller PUT。
- 即使`CACHE_LOCAL_REGULAR>0`也只能说文件存在、位置初步安全，不能证明缓存内容与当前运行态一致/规则业务可用。此测试不产生任何新的AI合格节点或出口国家。

## 四、唯一下一步

在家中iStoreOS TTYD执行**一次**固定版本的匿名规则集来源清点，回传终端状态即可。若实际是`inline`，可优先将其保留为原样直接允许私有解析；若是`file`/带已缓存`http`，须设计对缓存文件哈希、大小、内容校验和私有路径克隆后的离线`-t`；若HTTP无可用缓存、隐式自动路径、目录越界或Geo数据库依赖，继续HOLD，不得直接让私有`-t`下载规则或去碰正式缓存。**无论哪条分支，都不能在这个阶段安装监听器或改动现网。**

唯一命令（只读脚本，不会复制节点配置、访问任何规则下载URL或重跑旧验收）：

```sh
( umask 077; f="$(mktemp /tmp/ai_rules_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/b5d9ced83925768860f1aa2ada3834c84571f5e2/scripts/ai_rule_provider_inventory_readonly.rb"; then ruby "$f" || echo "INVENTORY_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "INVENTORY_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

输出字段为`INVENTORY_RESULT=RULE_PROVIDER_SHAPE_CLASSIFIED`时，只需将`TYPE_HTTP/TYPE_FILE/TYPE_INLINE`、`CACHE_*`、`RULESET_REFERENCE_PRESENT`、`GEO_REFERENCE_PRESENT`及`PROXY_PROVIDERS_PRESENT`匿名结果发回；遇`HOLD_*`只处理本次HOLD。现网继续`PRODUCTION_CONFIG=UNCHANGED LISTENER_INSTALLED=NO AI_AUTO_SWITCH=OFF`。

## 最终P0要求（不缩水）

路由器必须继续实现全部真实可用机场节点的ChatGPT/Gemini/NotebookLM独立资格，实际出口地区分组，随原OpenClash订阅成功增量维护及稳态故障接替；NotebookLM入口`location=unsupported`与登录/`icid`正负分支只能算预筛，真正来源导入/问答/引用且同出口的真实业务验收仍必需。手机端智能化只作为P1，已有三端订阅、Worker及非AI规则不动。
