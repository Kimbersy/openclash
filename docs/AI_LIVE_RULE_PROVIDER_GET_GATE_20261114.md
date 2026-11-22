# 2026-11-14 19:22 MRS文件头HOLD之后：现有Mihomo只读规则Provider运行态核对

## 实机回执与已验收边界

- [19:22用户真实回执](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_TWO_CACHE_RECEIPT_20261114_1922.md)：唯一大YAML的有界`payload`结构浅层`YAML_SHALLOW_PASS`，唯一MRS缓存的`MRS_HEADER=HOLD_MRS_MAGIC_UNKNOWN`，总`HOLD_TARGET_STRUCTURE`；没打开完整MRS或运行私有Mihomo`-t`，不能认定磁盘内容损坏，也不能推断运行中Provider是否已成功载入。
- 19:04实机20/20缓存元数据归类成功（19 YAML，1 MRS，18小YAML、1大YAML）；18:18 18小YAML静态基本结构通过；17:20 20/20缓存字节复制与清理通过；17:06 Geo三项FALSE/FALSE/PRESENT；17:33缺少`unshare`，完整IPv4/IPv6隔离未证明；15:46仅纯合成原生Mihomo`-t`通过。**这些检查均不重做**。
- 上游[Mihomo API文档](https://wiki.metacubex.one/en/api/)明确`GET /providers/rules`查询所有Rule Provider，而`PUT /providers/rules/{name}`是更新操作；本次只能GET。上游[MRSv1头定义](https://pkg.go.dev/github.com/metacubex/mihomo%40v1.19.34/rules/provider)为`{'M','R','S',1}`，真实文件不匹配时必须把磁盘格式问题留作独立HOLD，不伪造原生解析结论。

## 新增单文件只读运行态候选：已通过CI，用户尚未执行

- [固定源码 `f94c5f389a57fd5574af4624420e91dbd25a07ea`](https://github.com/Kimbersy/openclash/blob/f94c5f389a57fd5574af4624420e91dbd25a07ea/scripts/ai_live_rule_provider_readonly.rb)，仅加载实机已证可用的Ruby `psych`；外部`curl`此前在iStoreOS执行过，**不需要`timeout/open3/tempfile/uri/unshare`**。
- 唯一正式Mihomo进程必须符合既有PID/exe和私有配置路径门禁，配置必须仍有20份HTTP Rule Provider及1份声明为MRS；从正式配置内部内存读取已有Controller设置、secret。限定配置Controller绑定`127.0.0.1`或`0.0.0.0`，只发向`http://127.0.0.1:PORT/providers/rules`的一次GET，并且验证`/proc/net/tcp` loopback/wildcard IPv4 LISTEN socket inode确属该正式Mihomo进程；GET前后均核对归属，拒绝仅WAN地址同端口侦测假阳性。其它绑定/无socket/认证失败一律HOLD。
- Bearer秘钥只由Ruby向curl stdin传递，在argv、日志、终端中均不输出；不打印原始响应、Provider/代理名称、规则明文、URL、IP或任何凭据。仅输出`LIVE_RULE_RESULT`、`CONFIG_PROVIDER_COUNT`、`API_PROVIDER_COUNT`、`API_EXPECTED_PRESENT/MISSING`、`API_EXTRA_UNTRUSTED`、`API_RULECOUNT_POSITIVE/ZERO/UNKNOWN`、`MRS_RUNTIME_RULECOUNT=POSITIVE/ZERO/UNKNOWN/ABSENT`等匿名字段。
- 限制connect 2秒、总7秒、响应1.5MB；不允许curl代理、跳转或访问非HTTP协议。所有布局/端口/鉴权/响应不可确定时返回保守HOLD；无`PUT/POST/PATCH/healthcheck`、无Controller修改、Provider刷新、第二核心、端口安装、策略切组或生产写入。
- **验收意义上限**：API中Provider名字存在证明当前查询的核心报告已注册，`ruleCount>0`表明API声明有规则条目；`0`或未知应保留异常/未证实分类。**即使MRS Provider返回正数，也不代表磁盘文件头正确、二进制规则内容完整、运行内存与缓存字节相同、订阅最新更新、三项AI真实业务合格**。
- [完整CI #43590384799](https://github.com/Kimbersy/openclash/actions/runs/43590384799) `completed/success`，包括新工具8组48合成断言、路由器最小依赖门禁、P0候选逻辑、三端/非AI回归、合成原生Mihomo语法测试；**CI ≠ 家中当前API执行成功**。代码仅在OpenClash Draft候选分支，未修改正式仓库main/路由器/Worker和手机订阅。

## 唯一下一步（安全只读实机回执；出现HOLD不要重试）

iStoreOS TTYD执行以下一次性固定Git源码命令。外层curl只下载GitHub公开单文件脚本到`/tmp`，脚本内部只会向本机127.0.0.1发起一次有界GET：

```sh
( umask 077; f="$(mktemp /tmp/ai_rulelive_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/f94c5f389a57fd5574af4624420e91dbd25a07ea/scripts/ai_live_rule_provider_readonly.rb"; then ruby "$f" || echo "LIVE_RULE_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "LIVE_RULE_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

回传`LIVE_RULE_RESULT`和全部匿名`API_* / MRS_RUNTIME_RULECOUNT`行。若`HOLD`，先审查脚本输出类别（例如本地Controller绑定不匹配），**不要安装工具或改端口/secret/核心配置来凑通过**。即使只读GET成功也不授权真实私有配置的Mihomo`-t`、任何Listener安装、自动切换。真正AI业务、出口地理与刷新接替属于独立P0未完验收。

VPS继续暂缓，源机场/Worker/三端非AI行为不变。
