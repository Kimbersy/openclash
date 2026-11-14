# 2026-11-14 22:47 UCI订阅源元数据误报39孤立桶：按section类型修复与新实机门禁

## 先前实机证据（不可重做）

- [22:47用户实际iStoreOS TTYD回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_UCI_SUBSCRIPTION_HOLD_RECEIPT_20261114_2247.md)：固定旧源码`31d9611d49877ebe9c3689000b8bbbb1834ed99a`已实际运行、仅本地`uci -q show openclash`，输出`HOLD_UCI_SUBSCRIPTION_STATUS_AMBIGUOUS UCI_SUBSCRIPTION_SECTION_COUNT=1 UCI_EXPLICIT_ENABLED_COUNT=1 UCI_EXPLICIT_DISABLED_COUNT=0 UCI_ENABLE_FLAG_UNKNOWN_COUNT=0 UCI_ENABLE_FLAG_CONFLICT_COUNT=0 UCI_ENABLED_ADDRESS_MISSING_COUNT=0 UCI_ORPHAN_OPTION_BUCKETS=39 UCI_SELECTED_CONFIG_DECLARED=YES UCI_AUTO_UPDATE=ENABLED UCI_UPDATE_CADENCE=DAILY`。**39并非39个机场订阅或真实损坏项。**
- 22:29两份现行源/核心运行配置**58/58完整字段一致**实机PASS；22:20正式IPv4本机API`GET /proxies` 58/58预期叶名字PASS（官方内置`PASS-RULE`已识别）；21:09规则Provider20/20在正式内核注册且正数PASS。这些绝不重跑。
- 远程订阅成功刷新、源贡献节点归属、运行核心内存凭据及ChatGPT/Gemini/NotebookLM真实业务资格/出口国家仍未证实。

## 已修复的具体范围缺陷（代码与CI，不是新实机）

旧单文件脚本遍历`uci show openclash`时，凡任意section的`.enabled`、`.enable`、`.address`都会纳入`options`，然后仅以`config_subscribe`名单判断“孤立”，错误地把其他**正常已声明类型**的选项算成订阅来源异常（现场39个是这种风险的表现，实际类型需新版分类确认）。

- 新固定候选源码[Git `a0b6cc7f0f5dd1c7f78c3fc5c43bf68e50877732`](https://github.com/Kimbersy/openclash/blob/a0b6cc7f0f5dd1c7f78c3fc5c43bf68e50877732/scripts/ai_active_subscriptions_metadata_readonly.rb)（请以该完整提交为不变基线）。
- 两遍**本机UCI读取内容的纯字符串解析**：先解析全部`openclash.<section>=<type>`的声明并区分`config_subscribe`与其他声明类型，再只统计`config_subscribe`中启用/禁用/地址；其他已声明的非订阅类型仅匿名计入`UCI_NON_SUBSCRIBE_OPTION_BUCKETS_SKIPPED`，不被误判成未声明的机场订阅。针对真正缺少section声明的`enabled/enable/address`则继续计入`UCI_ORPHAN_OPTION_BUCKETS`，保持HOLD；相同节重复声明、类型冲突、源状态冲突、源地址缺失、无启用源仍独立HOLD，不为过关放宽安全判定。
- 原`UCI_SUBSCRIPTION_SECTION_COUNT`、`UCI_EXPLICIT_ENABLED_COUNT`、`UCI_EXPLICIT_DISABLED_COUNT`、`UCI_ENABLE_FLAG_UNKNOWN_COUNT`、`UCI_ENABLED_ADDRESS_MISSING_COUNT`、`UCI_SELECTED_CONFIG_DECLARED`、`UCI_AUTO_UPDATE`及`UCI_UPDATE_CADENCE`保持原口径；没有任何源名称、URL、密码、地址、真实节点/端口、源完整UCI原文输出。**计数39若转移到已排除非订阅类只能说明它们属于有类型声明的其他配置节，不代表所有订阅已合并或刷新成功。**
- [完整GitHub CI #43607048138](https://github.com/Kimbersy/openclash/actions/runs/43607048138) `completed/success`：严格模拟用户实机“1明确启用 + 39其他合法节字段”的合成样本以及“13个合法非订阅节×3字段”的边界，检验真实孤立选项继续HOLD、节重复和类型冲突继续HOLD、每周/每日/定时计划、泄密保护、iStoreOS Ruby零额外`require`依赖，以及原P0、三端/非AI/Mihomo原生合成CI无回归。**只是CI，还不是新版家中真实PASS**。

## 当前唯一下一步：固定SHA，一次新版本本地UCI匿名回执

iStoreOS TTYD仅执行下面这**一条新固定版本命令**一次，外层`curl -4`下载GitHub固定单文件至`/tmp`，脚本本身没有外网/代理/Controller访问，只执行本机`uci -q show openclash`：

```sh
( umask 077; f="$(mktemp /tmp/ai_subtype_XXXXXX)" || exit 1; if curl -4 -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/a0b6cc7f0f5dd1c7f78c3fc5c43bf68e50877732/scripts/ai_active_subscriptions_metadata_readonly.rb"; then ruby "$f" || echo "SUBSCRIPTION_METADATA_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "SUBSCRIPTION_METADATA_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

用户只需回传`SUBSCRIPTION_METADATA_RESULT`、`UCI_ORPHAN_OPTION_BUCKETS`、`UCI_NON_SUBSCRIBE_OPTION_BUCKETS_SKIPPED`及原有其它匿名UCI计数（截图即可）。如继续HOLD，**不得要求修改原订阅、打开IPv6或重跑旧`31d9611d`脚本**，从新分类码继续开发。即使`UCI_ENABLED_SOURCE_METADATA_CLASSIFIED`也只证明本地UCI状态可分类，`ENABLED_SUBSCRIPTION_MERGE_PROVENANCE=NOT_VERIFIED REMOTE_SUBSCRIPTION_REFRESH_SUCCESS=NOT_VERIFIED MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED AI_BUSINESS=UNKNOWN`；后续转向真实更新日志或来源身份绑定、三平台业务与双源IPv4出口资格及稳定接替。现有OpenClash、Worker、三端及非AI不改，`LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`，VPS继续HOLD。
