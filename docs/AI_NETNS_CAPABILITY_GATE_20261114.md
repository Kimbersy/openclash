# 2026-11-14 17:20缓存字节验收后：只读NetNS能力门禁

## 已经实机通过（不得重复）

- [17:20 规则缓存字节复制实机回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_CACHE_BYTECOPY_RECEIPT_20261114_1720.md)：`BYTECOPY_RESULT=BYTE_COPY_VERIFIED CACHE_FILES_VERIFIED=20 TEMP_CLEANUP=YES`；无正式配置更改、未运行真实私有配置`-t`。
- [17:06 Geo三项回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_GEO_FLAGS_DEVICE_RECEIPT_20261114_1706.md)：`GEO_DAT_MODE=FALSE GEO_AUTO_UPDATE=FALSE GEO_CUSTOM_URL=PRESENT`。
- 官方[Mihomo Rule Provider文档](https://wiki.metacubex.one/en/config/rule-providers/)区分`type:http`远程下载/更新与`type:file`本地；[通用Geo配置说明](https://wiki.metacubex.one/en/config/general/)区分Geo模式、自动更新和下载源。自定义下载源存在不证明将来任何解析都不会访问外网。

## 本轮工程增量（仅候选代码与CI）

- 新增纯离线[外部资源依赖审计器](../scripts/ai_real_config_resource_gate.py)，用合成配置识别顶层和嵌套的DNS Geo、Rule-Set、脚本/外部UI、远程Provider、Geo配置状态变化等；即便没有发现此类引用，仍然`HOLD_NETWORK_ISOLATION_UNPROVEN`，绝不授权真实`-t`。不对外输出节点/密码/URL/私有配置；[完整CI #43580568551](https://github.com/Kimbersy/openclash/actions/runs/43580568551) success。
- 新增[独立 `scripts/ai_netns_capability_readonly.sh`](../scripts/ai_netns_capability_readonly.sh)用于**只检查路由器上能否启动一个瞬时、与原进程不同的网络命名空间**；新命名空间内只执行shell+读取`/proc/self/ns/net`，不运行Mihomo，不创建配置副本，不读取任何规则/节点，**不向外发网络请求、不修改现有路由表/接口/防火墙**。即使获得`CHILD_NAMESPACE_DISTINCT`，也明确`NETWORK_EGRESS_DENIAL=NOT_PROVEN`：必须独立证明完整IPv4/IPv6网络隔离、无遗留外部依赖、敏感材料全留在设备本地才能计划真实配置解析。
- 只依赖iStoreOS基础`sh`、`readlink`，如无`unshare`或内核不支持新网络命名空间，明确`HOLD_*`并停止，不安装软件、不要求调整生产系统。
- 原公开`main`、已运行路由器/Worker、OpenClash策略组及Android/iOS订阅均未改。

## 唯一下一步（需一份新的无敏感实机回执）

在 iStoreOS TTYD **只执行一次**以下固定源码commit命令（该脚本只做上述能力检查，固定`30187cd5d9a71600775c8c61e3ab785ffc1ac163`）；不重复20缓存/Geo/15:46纯合成Mihomo：

```sh
( umask 077; f="$(mktemp /tmp/ai_netns_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/30187cd5d9a71600775c8c61e3ab785ffc1ac163/scripts/ai_netns_capability_readonly.sh"; then sh "$f" || echo "NETNS_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "NETNS_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

仅回传`NETNS_RESULT`及`NETWORK_EGRESS_DENIAL`。返回`HOLD_*`不是生产网络故障，不重复执行旧代码。若`CHILD_NAMESPACE_DISTINCT`也**不代表能直接跑真实配置`-t`**：下一阶段在候选分支证明严格不联网和各外部依赖的资源模型后再决定具体行动。若不支持NetNS，选择无需生产改动的其它隔离手段或停在安全静态审计，不建议开启防火墙修改或安装依赖来凑测试。

**生产状态不变**：`BUSINESS=UNKNOWN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`；全P0合格节点池/三平台真实业务/真实地区/增量订阅/稳态接替不可缩水。VPS仍未购买。
