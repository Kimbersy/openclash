# 2026-11-14 17:33 NetNS HOLD 之后：低资源纯静态Rule Cache门禁

## 基线与实际设备事实

- 已通过：[17:20用户实机20/20缓存字节复制与清理原回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_CACHE_BYTECOPY_RECEIPT_20261114_1720.md) `BYTECOPY_RESULT=BYTE_COPY_VERIFIED CACHE_FILES_VERIFIED=20 TEMP_CLEANUP=YES`；不能当作规则格式语义已通过。
- 已通过：[17:06用户实机Geo三项分类](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_GEO_FLAGS_DEVICE_RECEIPT_20261114_1706.md)：`GEO_DAT_MODE=FALSE GEO_AUTO_UPDATE=FALSE GEO_CUSTOM_URL=PRESENT`。
- **最新阻断**：[17:33用户实机NetNS能力HOLD](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_NETNS_HOLD_RECEIPT_20261114_1733.md)：`NETNS_RESULT=HOLD_TOOL_UNAVAILABLE NETWORK_EGRESS_DENIAL=NOT_PROVEN`，iStoreOS无法找到`unshare`命令；不代表内核不支持、不安装软件/更改防火墙凑测试，不能对真实配置跑任何未隔离Mihomo `-t`。
- 官方[Mihomo Rule Provider规范](https://wiki.metacubex.one/en/config/rule-providers/)区分`yaml/text/mrs`规则格式，`mrs`只允许`domain/ipcidr`行为。文本/YAML静态核对不代表Mihomo真实编译解析，也不能证明规则语义无误、运行内核已载入或远程HTTP更新完成。

## 本轮新增的零外联工程候选

- 独立[`scripts/ai_rule_cache_structure_readonly.rb`](../scripts/ai_rule_cache_structure_readonly.rb)：**仅依赖iStoreOS实机已加载成功的Ruby`psych`**，只读当前唯一Mihomo运行配置与20份本地规则缓存，限制配置20MiB/缓存单份8MiB/总48MiB；YAML在交给Psych解析前限制到**1MiB**，防止精简路由器大体积YAML解析内存飙升。不会调用Mihomo、网络命令、控制器API、额外核心，也不会创建含规则/私密信息的副本。
- 明确识别`yaml`的`payload: [字符串]`结构、`text`有效UTF-8非空非注释行与`mrs`二进制；**遇到MRS只记录数量并返回`HOLD_MRS_BINARY_UNPARSED`，不会自称验证MRS**。其它错误提供固定HOLD码：不安全路径、symlink、重复/缺失缓存、格式与行为不匹配、YAML解析失败、内存预算/文件尺寸超额、Geo状态与17:06不同等。
- 私密规则文本、Provider名称、机场服务器地址、密码、URL均不打印/不上传；只输出匿名`STRUCTURE_RESULT`、`CACHE_YAML_STATIC`、`CACHE_TEXT_STATIC`、`CACHE_MRS_UNPARSED`。**即使`STATIC_STRUCTURE_PASS`也继续输出`MIHOMO_SYNTAX=NOT_VALIDATED NETWORK_ISOLATION=NOT_PROVEN`**；实际`-t`和正式Listener/切线仍然HOLD。
- 固定源码最终提交以Git仓库当次CI为准。合成单元测试包含20 YAML通过，混合text+MRS明确HOLD，非法格式/编码、空payload、不安全路径、文件超额、1MiB YAML内存上限、Geo状态变化、私密材料不出诊断。原完整AI/非AI/三端回归与精简路由器运行时门禁被加入现有候选Workflow。
- 不修改正式`main`、用户iStoreOS生产配置、HTTP Provider、Cloudflare Worker/KV、Android/iOS公共订阅，不自动启用AI切换。

## 唯一下一步（取决于最终CI）

完成上述候选脚本的**最新完整GitHub CI**确认并回读固定源码。仅CI全PASS后，才可以向用户提供一条可在TTYD运行的固定SHA的**仅静态缓存结构检查**命令；只回传四个匿名字段。若HOLD，不重试旧 NetNS、Geo、缓存字节门禁；先在候选源码层分析具体格式限制。下一阶段独立研究可证明完整IPv4/IPv6出网封锁的隔离方式，明确以后真实配置`-t`不得在未知网络暴露下运行。

P0最终目标：全部有效订阅节点、三平台真实业务资格、真实地区动态组、订阅增量、稳态主备；这些均未实机交付。当前`BUSINESS=UNKNOWN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`，VPS仍属条件性备选。
