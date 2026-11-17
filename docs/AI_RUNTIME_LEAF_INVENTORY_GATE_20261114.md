# 2026-11-14 21:09规则Provider运行态验收后：正式Mihomo全部叶节点只读覆盖核对

## 一、已通过的实机证据（不重做）

- [用户21:09 IPv4环回Controller GET真实回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_LIVE_RULE_PROVIDER_PASS_20261114_2109.md)：正式Mihomo规则Provider在API中配置20、登记20、全部报告正数规则条目；唯一MRS Provider同样报告正数。**20表示规则Provider，不代表机场节点只有20条**。
- [20:54唯一正式Mihomo Controller socket证据](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_SOCKET_OWNER_IPV6_RECEIPT_20261114_2054.md)：配置IPv4 wildcard，底层IPv6 wildcard双栈监听、PID/fd匹配；21:09已经实际确认`127.0.0.1`的强制IPv4请求可用。用户明确IPv4优先，不为此改变IPv6出口或家庭DNS/路由。
- 19:22大YAML浅层结构通过但磁盘MRS文件头HOLD；19:04 20缓存格式分类；17:20 20缓存逐字节复制及清理；17:06 Geo FALSE/FALSE/PRESENT；15:46仅纯合成Listener本机Mihomo`-t`通过。**不得重复历史脚本**；规则格式和磁盘/内存字节一致性不能被本阶段冒称。
- 历史旧设备“58节点/58个名字”是当时源与API快照，**不是永久固定节点数量**。动态订阅更新后节点可能新增、删减或同名换连接参数，不能直接继承旧AI业务资格。

## 二、工程成果（未在家中执行此新脚本）

- 复用原有[订阅节点分类候选`ai_subscription_inventory.rb`](../scripts/ai_subscription_inventory.rb)和[现有运行态名字覆盖候选`ai_live_membership_readonly.rb`](../scripts/ai_live_membership_readonly.rb)的已验证设计，不重造服务选择规则。
- 新增[固定源码Git `7932c0b7ca7e7288e36ed4e824baf40b1e0fe1d7` 的单文件 `ai_runtime_leaf_inventory_readonly.rb`](https://github.com/Kimbersy/openclash/blob/7932c0b7ca7e7288e36ed4e824baf40b1e0fe1d7/scripts/ai_runtime_leaf_inventory_readonly.rb)，仅使用已实机证可用的Ruby`psych`及curl；与21:09已验证接口通路相同，强制`--ipv4`到同一正式Mihomo已归属的本机`127.0.0.1`，前后核验socket，`GET /proxies`而非PUT、不切线、不更新订阅、不重启核心。
- 从**当前正在运行的配置**取所有嵌入真实proxy叶节点及组名，将`GET /proxies`返回的组、内置节点和叶节点分类；只输出匿名`CONFIG_EMBEDDED_LEAF_COUNT`、`API_EXPECTED_LEAF_PRESENT/MISSING`、`API_EXTRA_UNTRUSTED_LEAF`、`API_UNACCOUNTED_GROUP`、`API_EXPECTED_AS_GROUP`。出现同名冲突、意外组、多余/缺失叶节点或未知proxy-provider动态模式一律HOLD；不打印节点、用户名、连接IP、端口、密码、API秘钥。响应限3MB、超时7s。
- 此检查区分**规则Provider**与**机场proxy-provider**，若后者在当前配置不为空，明确`HOLD_PROXY_PROVIDER_MODE`，不伪造全量节点覆盖。即使全部名字匹配，也明确`LIVE_FULL_CONNECTION_FINGERPRINTS=NOT_VERIFIED ENABLED_SUBSCRIPTION_SOURCE_COVERAGE=NOT_VERIFIED`，**尚不能证明配置中的服务端、端口、协议或凭据已经被运行核心以最新参数加载**，也不说明机场远程订阅刷新成功。
- [完整CI #43598892840](https://github.com/Kimbersy/openclash/actions/runs/43598892840) `completed/success`：58/动态74叶节点、组和内置项排除、缺失/额外叶及意外组HOLD、proxy-provider尚不支持的保护、IPv4与安全匿名输出、iStoreOS精简依赖、原P0全节点/地区/增量合成逻辑、三端与非AI冻结回归均通过。**CI通过不等于新设备回执**。代码只在OpenClash Draft候选分支，正式系统和Worker/三端都没改。

## 三、唯一下一步：一次正式Mihomo叶节点匿名GET

在 iStoreOS TTYD **只执行以下一条固定源码命令一次**（公开脚本通过IPv4下载至`/tmp`，脚本自身只向`127.0.0.1`发单次有界只读GET）：

```sh
( umask 077; f="$(mktemp /tmp/ai_leafinv_XXXXXX)" || exit 1; if curl -4 -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/7932c0b7ca7e7288e36ed4e824baf40b1e0fe1d7/scripts/ai_runtime_leaf_inventory_readonly.rb"; then ruby "$f" || echo "LEAF_INVENTORY_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "LEAF_INVENTORY_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

仅回传`LEAF_INVENTORY_RESULT`和匿名`CONFIG_*/API_*`计数（截图即可）。如出现`HOLD`，根据阻断码在候选代码层排查，不重跑之前21:09规则Provider、20:54socket、Geo和缓存脚本。不要求用户现在调整密码、订阅、IPv6、Controller端口或安装其它依赖。

## 四、后续唯一方向（本轮不会提前伪称完成）

若当次运行态名字覆盖完整：下一阶段对现行**所有启用订阅**建立实际加载和完整连接参数指纹的安全准入（名字相同绝不代表凭据/线路参数一样）；不重扫历史58条。然后按P0契约进入ChatGPT/Gemini/NotebookLM三平台分别真实登录/流式/工作区业务验证、双源实际IPv4出口国家、订阅成功更新后的增量身份撤销或继承、按实际国别的全部合格节点及稳态防抖接替。未建立真实资格证据前无节点可标为`BUSINESS_VERIFIED`，不得启用生产AI自动切线。

`BUSINESS=UNKNOWN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`，VPS继续HOLD。
