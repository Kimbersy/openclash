# 2026-11-14 15:22 实机后：取消版本字符串门禁，改验 Mihomo 实际监听器支持

## 真实证据和决策

用户15:22 iStoreOS TTYD执行固定Git `fae4f636`的只读版本专项脚本，输出`MIHOMO_VERSION_RESULT=HOLD_VERSION_FORMAT_UNRECOGNIZED`、`MIHOMO_VERSION=UNAVAILABLE`、`PRODUCTION_WRITES=NONE AUTO_SWITCH=OFF`。这证明`-v`有非空输出但当前正则不认可；**不能推断内核损坏、版本老旧、listeners不支持**。15:02已通过的唯一正式核心识别、17881未监听和运行配置基础结构全部沿用，不再让用户重做。

**设计决策：** 能否使用Mihomo原生`listeners[].proxy`，应由当前正式安装的Mihomo二进制对隔离的纯合成配置执行`-t`来验，**不必先提取X.Y.Z三段版本号**。这不改变必须先验证真实AI网站尤其NotebookLM的最终业务门槛，也不缩水全部订阅节点/三服务/国家组/自动订阅/稳态主备的P0范围。

## 本轮完成（固定Git与可复核CI）

- [独立Ruby核心脚本](https://github.com/Kimbersy/openclash/blob/418a42c39c3f4e08cae3a3ff7bee8dbf6014e4fb/scripts/ai_notebook_native_capability_test.rb)，**不含任何require/gem**，复用此前真实验证过的`/proc`唯一正式Mihomo进程识别规则，不需要读取机场、用户现网真实YAML或密钥。
- 创建**仅一次**0700私人`/tmp/ai_nb_native_<随机>`目录和0600合成YAML。YAML仅有`SYNTHETIC_NO_NETWORK`（文档保留IP）、独立`__AI_NOTEBOOK_PROBE_ONLY__`select组（首项`REJECT`）及仅绑定`127.0.0.1:17881`的HTTP listener；没有订阅、外部provider、Google登录、NotebookLM来源或真实节点。注意：测试没有把listener加载进**现网运行的Mihomo**。
- 临时启动**唯一一次**`/proc/<活动Mihomo PID>/exe -t -d <新私有目录> -f <合成YAML>`短时**配置语法验证子进程**；并非第二个常驻代理核心，不选线/不启用监听端口。子进程输出不回传，可报告`NATIVE_LISTENER_SYNTAX_PASS`/`HOLD_NATIVE_LISTENER_SYNTAX_REJECTED`/`HOLD_NATIVE_LISTENER_TEST_TIMEOUT`等匿名状态；12秒上限，超时只杀新子进程，不向现有服务发信号。结束后清除仅属于本次合成目录的文件及子目录（不跟随符号链接）。遇清理失败报告`HOLD_PRIVATE_TMP_CLEANUP`。
- [固定源码Git `418a42c39c3f4e08cae3a3ff7bee8dbf6014e4fb`](https://github.com/Kimbersy/openclash/commit/418a42c39c3f4e08cae3a3ff7bee8dbf6014e4fb)、[完整CI #43571381191](https://github.com/Kimbersy/openclash/actions/runs/43571381191) `completed/success`：新增Ruby脚本测试、精简iStoreOS依赖契约、**官方Mihomo v1.19.34二进制对同一份Ruby合成YAML的原生`-t`测试**、虚构缓存清理不跟随符号链接、12秒有界退出、原全量/地区/NotebookLM/三端非AI冻结回归均通过。**CI≠用户设备已通过**。

## 设备最短唯一下一步（当前未执行）

在用户方便时iStoreOS TTYD执行**这一条固定SHA的合成配置原生功能测试**，无需再试-v，也无需重复15:02端口/配置/58节点检查：

```sh
( umask 077; f="$(mktemp /tmp/ai_nb_cap_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/418a42c39c3f4e08cae3a3ff7bee8dbf6014e4fb/scripts/ai_notebook_native_capability_test.rb"; then ruby "$f" || echo "NATIVE_CAPABILITY=HOLD_SCRIPT_RUNTIME"; else echo "NATIVE_CAPABILITY=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

**验收：** `NATIVE_CAPABILITY=NATIVE_LISTENER_SYNTAX_PASS`且`TEMP_CLEANUP=YES`，只意味着本机实际核心可解析这份单核独立listener语法；**不证明现网实际加载或服务能用**。遇`HOLD_*`只针对对应问题处理。运行时可能在`/tmp`产生短时合成缓存，只清理本次专用目录；不会写正式OpenClash配置、订阅、Worker或修改选择。用户此前要求低能耗：本脚本不是长期程序、不起常驻守护进程，至多一次12秒功能门禁。

**待后续另行验收并申请授权**：真实私有配置副本`-t`、备份回滚、受控安装`127.0.0.1`隔离入口、读回测试组实际选中`REJECT`、已知NotebookLM支持/unsupported正负出口轻量CTA校准、真实来源导入/问答/引用同出口、全订阅增量自动组及稳态切换。没有安装授权不得直接应用或PUT生产设置。当前`BUSINESS=UNKNOWN AUTO_SWITCH=OFF`、现网未变。
