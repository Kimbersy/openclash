# 2026-11-14 21:56 运行态58/58叶节点匹配，1条额外记录的保守内置类型归类

## 实机证据（不得重复）

- [用户21:56固定`856dccce`实机回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_LEAF_INVENTORY_EXTRA_HOLD_RECEIPT_20261114_2156.md)：正式运行配置嵌入58条、Proxy-Provider 0；经正式PID/NetNS/socket归属校验后强制IPv4本机`GET /proxies`得到预期58/58名字、缺失0、未识别组0、错把叶节点当策略组0，**额外未分类记录1条**，所以`LEAF_INVENTORY_RESULT=HOLD_RUNTIME_LEAF_MISMATCH`。该记录究竟是官方内置出站还是额外真实节点尚未确认，不能称为机场第59条已加载节点。
- 21:53下载超时`HOLD_DOWNLOAD_UNAVAILABLE`仅对应当时GitHub Raw HTTPS未成功，新脚本未执行；21:56相同固定SHA现已成功下载执行，**此真实新证据覆盖旧下载阻断，不能让用户重试旧脚本**。21:40旧`GET /proxies`因fd归属误判可能而HOLD；21:09正式规则Provider 20/20正数API记录继续有效。全部历史Geo/MRS/缓存/Socket验收沿用，不重复。
- 本机生产`PRODUCTION_CONFIG=UNCHANGED PROVIDER_REFRESH=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`。完整节点连接参数指纹/机场全部启用订阅源/最新成功增量/三AI业务/双源IPv4出口国家全部未证实。

## 上游依据与新增工程

- 上游Mihomo [官方 built-in proxy policies](https://wiki.metacubex.one/en/config/proxies/built-in/)明确存在`DIRECT`、`REJECT`、`REJECT-DROP`、`PASS`、`PASS-RULE`、`COMPATIBLE`。先前代码`BUILTINS`遗漏`PASS-RULE`。上游 [AdapterType类型枚举](https://pkg.go.dev/github.com/metacubex/mihomo/constant)包含`PassRule`、`RejectDrop`、`Pass`等，**但并未通过实机证据确认那条额外记录就是PASS-RULE**。
- 对现有已通过CI且已在设备执行的IPv4-only节点清点代码进行**最小安全修订**，固定[Git源码 `cf3c1ff9c22a3ad570a970a8535a402a4ca3c651`](https://github.com/Kimbersy/openclash/commit/cf3c1ff9c22a3ad570a970a8535a402a4ca3c651)：内置只在名字和API实际`type`严格匹配时排除；`PASS-RULE`只接受`PassRule`，不接受同名`Trojan`等伪装节点；配置叶节点与内置名字/策略组冲突一律HOLD。
- 输出`API_EXTRA_PRESET_MATCHED` = 在实际API的内置对象中通过名称+type双重核对的总数量，**包括已有DIRECT/REJECT/GLOBAL等内置基线，不能把该数字当“新增机场节点数”**；另外`API_PASS_RULE_PRESET`独立计数该新支持内置对象。对仍未识别项输出`API_EXTRA_PRESET_TYPE_MISMATCH`、`API_EXTRA_SPECIAL_TYPE_UNCLASSIFIED`、`API_EXTRA_OTHER_UNCLASSIFIED`匿名计数，并将`API_EXTRA_UNTRUSTED_LEAF`保留为这三类的总数。任一非可信额外项仍`HOLD_RUNTIME_LEAF_MISMATCH`；只有预期节点匹配、未知记录为0、无额外组/叶节点错误才`LIVE_LEAF_NAME_COVERAGE_PASS`。
- **不会**打印实际多出对象的名字、代理type原值、服务器、节点地址/订阅密钥或HTTP响应；原强制`curl --ipv4`到已经核验归属的`127.0.0.1`、进程身份和socket前后校验、Token走curl stdin、单次GET、响应上限、精简Ruby仅`require 'psych'`均保持。源代码只在隔离候选分支，不修改设备配置、OpenClash转发、Worker/三端/非AI行为、Listener或自动切组。
- [GitHub完整CI #43602984998](https://github.com/Kimbersy/openclash/actions/runs/43602984998) `completed/success`：官方内置PASS-RULE正向分类、同名Trojan及其它不明对象保守HOLD、58/74动态节点、真实socket identity/FD异常、iStoreOS精简依赖、全部P0/三端/非AI回归通过。**这是合成CI，尚未取得实机新的API类型分类。**

## 唯一下一步：只对额外记录的安全类别完成一次新的固定SHA只读回执

在iStoreOS TTYD执行一次固定源码。外层仍`curl -4`仅下载GitHub固定SHA候选脚本到`/tmp`，内层仍只读取正式Mihomo本地IPv4`GET /proxies`；如curl Raw HTTPS下载超时则返回`HOLD_DOWNLOAD_UNAVAILABLE`，不对外网络切换或重复旧URL。

```sh
( umask 077; f="$(mktemp /tmp/ai_leafkind_XXXXXX)" || exit 1; if curl -4 -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/cf3c1ff9c22a3ad570a970a8535a402a4ca3c651/scripts/ai_runtime_leaf_inventory_readonly.rb"; then ruby "$f" || echo "LEAF_INVENTORY_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "LEAF_INVENTORY_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

仅回传`LEAF_INVENTORY_RESULT`与`CONFIG_*`、`API_*`匿名统计的截图即可。若`API_PASS_RULE_PRESET=1`且`API_EXTRA_UNTRUSTED_LEAF=0`、58个预期叶仍0缺失，则可确认这次额外记录是已知内置`PASS-RULE`，不是第59条外部机场节点；否则保留实际类别的HOLD，**不将未知对象放入AI节点池**。此轮实机只验证名字+API类型，不声称58条完整连接参数/业务合格。

下一主线：完成当前真正有效订阅源与58条实际连接参数指纹一致性保密核验，然后分ChatGPT/Gemini/NotebookLM三平台真实业务资格、真实IPv4双源出口国家、订阅成功增量和稳态故障接替。现时`BUSINESS=UNKNOWN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`，VPS仍暂缓。
