# 2026-11-14 Geo 三项真实回执后的缓存字节复制门禁（P0 阶段）

## 输入真实证据（不重跑）

- [家中17:06实机Geo匿名截图回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_GEO_FLAGS_DEVICE_RECEIPT_20261114_1706.md)：`GEO_RESULT=FLAGS_CLASSIFIED GEO_DAT_MODE=FALSE GEO_AUTO_UPDATE=FALSE GEO_CUSTOM_URL=PRESENT`。这解释了此前 `GEO_MODE_ENABLED=1`，**并不等于Geo自动更新开启**。
- 先前实机20个HTTP rule-provider缓存文件均位于当前Mihomo HomeDir、文件存在、无已知路径越界或symlink；**此前只检查存在性，没有验证内容和运行态**。
- 15:46真实Mihomo对无私有节点的纯合成Listener原生`-t`通过，不需要重复。
- 本任务完整范围见[家庭IT P0不可缩水契约](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_AI_P0_ACCEPTANCE_CONTRACT.md)。

## 本轮候选代码与通过的CI

- 新增只在iStoreOS上运行的 [`scripts/ai_rule_cache_byte_copy_gate.rb`](https://github.com/Kimbersy/openclash/blob/39dbfdb7b9b84e17f3009a25a53564f139cdbb28/scripts/ai_rule_cache_byte_copy_gate.rb)：**只需要此前家中实际证实可用的Ruby `psych`**；无`timeout/open3/tempfile/uri/Python`依赖、无远程请求、不开新内核、不读取Mihomo API、不调用`-t`、不改原正式配置和原20个HTTP Provider。仅将已存在的规则缓存文件在设备**本地受保护的临时目录**按64KiB流式复制，再逐字节与仍打开的源文件比对、复验源文件元数据，最后清理测试副本。
- 门禁：唯一正式Mihomo及其当前运行配置；Geo状态相对17:06未出现`geodata-mode=true`或`geo-auto-update=true`，且仍有自定义Geo URL；全部HTTP Provider显式规则缓存路径保持在真实HomeDir内部、拒绝`..`/符号链接/越界/重复路径、文件变动、不可读和不完整副本。每文件上限8MiB、总大小48MiB、最多2000份；超过就HOLD不扩大。脚本本身不解析规则内容语义，不创建私有YAML，也不判断Geo将来是否下载。
- `0700`随机私有临时目录、`0600`缓存副本，脚本正常或失败均尝试清理；只有`TEMP_CLEANUP=YES`才确认清理完成。**极端进程中止/断电仍需手工评估临时目录是否留存，不宣称强制中止后绝无残留。** 原始敏感规则内容永不上传到GitHub、不打印文件名、路径、Provider名、下载URL、账号或节点凭据。
- [本地合成Ruby测试](https://github.com/Kimbersy/openclash/blob/39dbfdb7b9b84e17f3009a25a53564f139cdbb28/tests/test_ai_rule_cache_byte_copy_gate.rb) 6组23项断言PASS；[固定源码提交`39dbfdb7`](https://github.com/Kimbersy/openclash/commit/39dbfdb7b9b84e17f3009a25a53564f139cdbb28)；[完整GitHub CI #43579741688](https://github.com/Kimbersy/openclash/actions/runs/43579741688) completed/success，相关字节复制、Geo、原Provider离线overlay、精简依赖、三端/非AI/P0回归均success。**CI只验证合成缓存及Linux测试环境，不是家中真实缓存/设备I/O已通过。**
- 代码只在`feature/egress-audit-20261111`候选分支、Draft PR #2中，正式`main`、用户iStoreOS、手机订阅/Worker未更新。

## 唯一下一步：一次设备本地字节复制与清理匿名回执

在iStoreOS TTYD执行**固定源码提交**的单条命令（仅下载脚本进入`/tmp`，执行后删除脚本；工作脚本仅限本地复制缓存，无Mihomo子进程）。不需要复制完整YAML或回传缓存文件：

```sh
( umask 077; f="$(mktemp /tmp/ai_cachegate_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/39dbfdb7b9b84e17f3009a25a53564f139cdbb28/scripts/ai_rule_cache_byte_copy_gate.rb"; then ruby "$f" || echo "BYTECOPY_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "BYTECOPY_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

只回传`BYTECOPY_RESULT`、`CACHE_FILES_VERIFIED`、`TEMP_CLEANUP`；若有`HOLD_*`状态也不自动重试，先按回执确定故障阶段。若`BYTECOPY_RESULT=BYTE_COPY_VERIFIED`且文件数覆盖全部现用Provider并`TEMP_CLEANUP=YES`，仅说明**复制时缓存字节与源文件一致且临时副本已清理**，**不证明规则内容合法、内核运行态加载、Geo资源可用、HTTP更新成功、AI业务或生产切线**。

## 后续独立的高风险门禁

仅在上一阶段成功后，设计**不访问公网的安全解析环境**、安全本地`type:file`映射和Geo自定义下载URL依赖分叉的候选，保持旧20个HTTP规则本身不变。任何无法保证解析离线或完整业务不变的条件均`HOLD`，不得为了`-t` PASS删除生产规则或私有节点，严禁重载正式核心/自动切换。真实Listener安装另需备份、明确授权、REJECT运行态回读与回滚验收。最终 P0 全量真实节点池与三平台/地区/订阅增量/稳态主备目标不缩水。
