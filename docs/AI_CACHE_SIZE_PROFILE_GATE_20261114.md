# 2026-11-14 18:18 YAML解析内存HOLD之后：一次性缓存元数据分布检查

## 实机证据与问题定位

- 用户18:18在iStoreOS TTYD执行固定 [`2db6f78` 静态结构脚本](https://github.com/Kimbersy/openclash/commit/2db6f78b7cd4e78f81590ea294f01defde82353e)，截图原始匿名事实保存于[家庭IT 18:18回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_CACHE_STRUCTURE_HOLD_RECEIPT_20261114_1818.md)：
  `STRUCTURE_RESULT=HOLD_YAML_MEMORY_BUDGET CACHE_YAML_STATIC=18 CACHE_TEXT_STATIC=0 CACHE_MRS_UNPARSED=0`，`MIHOMO_SYNTAX=NOT_VALIDATED NETWORK_ISOLATION=NOT_PROVEN`，`PRODUCTION_CONFIG=UNCHANGED RULE_CACHES=READ_ONLY LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`。
- 说明**第19个被尝试的YAML文件大于1MiB的Psych解析门禁**，用户设备没有因此发生异常。不能从18/0/0推出第20个文件格式，也不能证明大YAML规则损坏。**不能简单将Psych上限改为8MiB让路由器加载，先取得大小分布。**
- 17:20已通过20/20原缓存文件受保护复制和逐字节比对，17:06Geo实际为FALSE/FALSE/PRESENT，17:33 NetNS只是因为`unshare`命令缺失而HOLD，这些历史回执全部保持有效且不再重复运行。

## 工程交付（源码/CI而非用户实机）

- 新增仅需已在iStoreOS实机验证可用的Ruby `psych` 的[纯元数据脚本](../scripts/ai_rule_cache_size_profile_readonly.rb)；定位当前唯一正式Mihomo使用的配置，只解析已有运行配置的Provider**元数据**，对20份HTTP规则缓存仅使用`lstat`、`realpath`等文件元数据，不打开规则文件内容、不用Psych解析大YAML、不复制缓存，也没有任何HTTP或Mihomo控制调用。
- 匿名输出整个20份规则缓存的`yaml/text/mrs`格式数量、YAML文件`<=1MiB`与`>1MiB`数量、全部文件大小区间(`<=1MiB`、`>1MiB`、`>4MiB`)。不输出文件路径、具体大小、规则名、节点、密码、订阅/Geo URL。遇到symlink、越界、重复路径、单文件超过8MiB、总尺寸超过48MiB、来源目录发生变化时直接HOLD，不伪造全量检查成功。
- **纯粹是大小/类型分类**，不能称为内容格式校验通过；任何大型YAML仍`YAML_LARGE_SEMANTICS=UNPARSED`，任何真实配置的Mihomo `-t`依旧`NETWORK_ISOLATION=NOT_PROVEN`且禁止执行。
- 固定[候选源码Git `8399319e12bef780fe55be62fb7701cc7a33785d`](https://github.com/Kimbersy/openclash/commit/8399319e12bef780fe55be62fb7701cc7a33785d)，[完整GitHub Actions CI #43584996708](https://github.com/Kimbersy/openclash/actions/runs/43584996708) `completed/success`：新增全20缓存聚合、两份晚序大文件、混合格式、格式状态变化、路径/大小错误、精简Ruby依赖/无内容读取门禁，以及既有P0、Geo、三端与全部非AI冻结回归全部通过。**GitHub测试是合成数据，不代表家中真实元数据已取得。**
- 没有修改OpenClash默认生产分支、当前用户网络、20 HTTP Provider、DNS、Worker/KV、Android/iOS共享订阅或正式Mihomo。

## 唯一下一步：一次全20源大小/格式匿名回执

仅在iStoreOS TTYD运行一次固定 `8399319` 脚本；下载器`curl`只取得公开固定SHA脚本放进单个临时文件，脚本本身不联网，执行完删除自身，无其他磁盘写入。

```sh
( umask 077; f="$(mktemp /tmp/ai_cachemeta_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/8399319e12bef780fe55be62fb7701cc7a33785d/scripts/ai_rule_cache_size_profile_readonly.rb"; then ruby "$f" || echo "PROFILE_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "PROFILE_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

只需回传`PROFILE_RESULT`、`PROVIDER_COUNT`、`FORMAT_YAML/TEXT/MRS`、`YAML_LE_1M`、`YAML_GT_1M`及大小分桶（截图即可）。如HOLD先按实际门禁处理，不重跑前面18份内容检测、17:20缓存复制或17:33 NetNS工具测试。

**本步骤获得的是剩余未知两份的格式与全量大小分布**。之后只针对真正需要的超限YAML设计内存有界的流式浅层检查，并依风险保持`UNPARSED`语义；不要为了完成静态检查无条件调大Psych内存或伪造原生解析成功。最终P0必须覆盖完整机场有效节点、三AI真实业务资格、动态国家分组、订阅增量、稳态防抖故障接替；目前`BUSINESS=UNKNOWN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF`，不采购VPS。
