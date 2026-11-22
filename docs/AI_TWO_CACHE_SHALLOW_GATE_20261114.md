# 2026-11-14 19:04 20份缓存全量格式回执后的两份定向只读门禁

## 必须复用的实机证据（不重复）

- [用户19:04 iStoreOS真实匿名回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_CACHE_METADATA_RECEIPT_20261114_1904.md)：`PROFILE_RESULT=SIZE_FORMAT_CLASSIFIED`，`FORMAT_YAML=19 FORMAT_TEXT=0 FORMAT_MRS=1`，`YAML_LE_1M=18 YAML_GT_1M=1`，`ALL_GT_4M=0 PROVIDER_COUNT=20`，正式配置未改、缓存正文未读。
- 18:18[小YAML结构门禁](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_CACHE_STRUCTURE_HOLD_RECEIPT_20261114_1818.md)：前18份YAML通过基础Psych结构检查，第19份触发预设1MiB内存限制；不能据此认定内容损坏。
- 17:20[20/20规则缓存受保护复制/逐字节核对/清理PASS](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_CACHE_BYTECOPY_RECEIPT_20261114_1720.md)、17:06[Geo配置FALSE/FALSE/PRESENT](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_GEO_FLAGS_DEVICE_RECEIPT_20261114_1706.md)、17:33[路由器缺少unshare](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_NETNS_HOLD_RECEIPT_20261114_1733.md)已记录。**不重复运行旧脚本，不安装软件，不运行带用户真实配置的Mihomo `-t`。**

## 经过离线合成验证的新工程

- [固定源码 Git `60b4f7f79244c52bf006389c01bc29e67d84020d`](https://github.com/Kimbersy/openclash/commit/60b4f7f79244c52bf006389c01bc29e67d84020d)，新增独立、单文件 [`ai_two_cache_static_readonly.rb`](https://github.com/Kimbersy/openclash/blob/60b4f7f79244c52bf006389c01bc29e67d84020d/scripts/ai_two_cache_static_readonly.rb)。仅使用此前已确认可用的Ruby核心方法和 `require 'psych'`，无需`unshare/timeout/open3/tempfile`。
- 不重新解析18份小YAML。只读取**恰好1份＞1MiB且≤4MiB的YAML**以及**恰好1份≤1MiB的MRS**，在打开前核对整个Provider清单的路径、唯一HomeDir边界、文件大小和Geo状态是否与19:04回执匹配；路径跨界、符号链接、来源格式改变、文件变化就HOLD。
- 大YAML仅以最多16KiB一次的`gets`逐行读取，保守检查顶层`payload:`与下方非空的一维列表行、UTF-8、NUL、行长、条目数上限。不创建大内存Psych对象。遇到复杂多行YAML/未知布局时返回`HOLD_YAML_COMPLEX_LAYOUT`，不把真实有效但不符合该浅层结构的规则误报为已损坏。
- MRS只读取文件开头4个字节，比对上游 [Mihomo Rule Provider Go包公开的 `MrsMagicBytes = {'M','R','S',1}`](https://pkg.go.dev/github.com/metacubex/mihomo/rules/provider)；**匹配只代表MRS v1文件头一致，不代表余下二进制规则正确、可被现有内核解析或已加载。** [官方Mihomo Rule Providers文档](https://wiki.metacubex.one/en/config/rule-providers/)强调`format:mrs`只支持`domain/ipcidr`。
- 新工具仅输出匿名状态`TARGET_RESULT`、`LARGE_YAML_SHALLOW`、`MRS_HEADER`，明确`MRS_BINARY_CONTENT=NOT_PARSED YAML_FULL_SYNTAX=NOT_VALIDATED MIHOMO_SYNTAX=NOT_VALIDATED NETWORK_ISOLATION=NOT_PROVEN`；不打印真实URL、路径、节点、规则正文、账户或密码；不改变正式配置/规则/Worker/三端、不调用Mihomo/Controller或网络，不安装Listener或自动切线。
- [GitHub完整CI #43588785598](https://github.com/Kimbersy/openclash/actions/runs/43588785598)已`completed/success`，包含大YAML和MRS正/负合成测试、最小Ruby运行时依赖、Geo资源门禁、20缓存门禁、P0合成候选、三端订阅与非AI冻结回归。**CI不是家中这两份真实缓存已通过的实机证据**。源码仍仅在OpenClash Draft候选分支，未发布生产变更。

## 唯一下一步（一次用户iStoreOS TTYD匿名只读回执）

执行固定提交 `60b4f7f79244c52bf006389c01bc29e67d84020d` 的以下**唯一**命令。外层使用`curl`只下载固定公开脚本到`/tmp`并删除，下载脚本本身没有出网代码，不启动额外Mihomo核心，不生成私人缓存副本。

```sh
( umask 077; f="$(mktemp /tmp/ai_two_cache_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/60b4f7f79244c52bf006389c01bc29e67d84020d/scripts/ai_two_cache_static_readonly.rb"; then ruby "$f" || echo "TARGET_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "TARGET_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

只回传`LARGE_YAML_SHALLOW`、`MRS_HEADER`与`TARGET_RESULT`三项；出现`HOLD`不要重复旧脚本或私自扩大YAML内存上限，先定位类型。即使`TARGET_RESULT=LIMITED_STATIC_CHECKS_COMPLETE`，亦**不能**启动真实配置的无网络隔离`-t`或宣称AI已上线。

下一阶段应优先评估**现有Mihomo运行态只读API是否能够匿名确认20个Provider已加载**，不再围绕文件格式重复收集微小回执；如需进一步私有完整配置解析，必须先解决全IPv4/IPv6外联硬隔离。全P0仍需所有真实机场节点、ChatGPT/Gemini/NotebookLM独立业务资格、实测出口国家、增量更新和防抖故障接替；VPS仍暂缓。
