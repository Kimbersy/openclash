# 2026-11-14 15:02 iStoreOS 实机版本号唯一阻断：专项只读诊断

> **本页优先级高于先前整套准入命令**。用户 15:02 实机已运行固定 `0ed2a1b`，并取得：
>
> - `CORE_PROCESS=UNIQUE_OPENCLASH` ✅
> - `PORT_17881=NOT_LISTENING` ✅（15:02快照；灰度前必须重新确认）
> - `RUNNING_CONFIG=CONFIG_STRUCTURALLY_READY` ✅（结构初验，非完整凭据/正式核心 -t）
> - `CORE_VERSION=UNAVAILABLE` / `ADMISSION=HOLD_CORE_VERSION_UNKNOWN` ⚠️
> - `PRIVATE_COPY_TEST=NOT_RUN`、`NODE_BUSINESS=UNKNOWN AUTO_SWITCH=OFF PRODUCTION_WRITES=NONE` ✅
>
> **不能把核心版本未知说成核心坏了、OpenClash版本落后或监听器不兼容，也不能重新要求已过的端口与配置检查。**

## 根因定位与只做必要修改

旧 `ai_notebook_router_admission_readonly.rb` 的 `version_from_command` 把版本命令的 `stderr` 重定向到 `/dev/null`，而所有异常都笼统转为 `UNAVAILABLE`。仅凭15:02输出**无法**判定是核心 `-v` 写到stderr、输出为空、输出格式不同、Ruby命令启动失败还是超时。

新加**只读、仅诊断版本**的单文件脚本：
- [`scripts/ai_mihomo_version_only_readonly.rb`](https://github.com/Kimbersy/openclash/blob/fae4f6362b0b40f8726f014cb44d6dc46ab9c892/scripts/ai_mihomo_version_only_readonly.rb)：无需任何 `require`、不依赖 `timeout`/`open3`/`uri`/`tempfile`；沿用原已验证的 /proc 唯一活跃内核定位方法，执行**仅该活动进程的可执行文件**一次 `-v`，使用 BusyBox `/bin/sh` 合并 `stdout` 和 `stderr`，最多三秒，仅输出经正则过滤的 `X.Y.Z` 或固定匿名错误状态，绝不打印PID、路径、节点名、机场地址、原始命令报错或密钥。不会读取端口、再次解析现有配置或安装配置。
- [合成测试](https://github.com/Kimbersy/openclash/blob/fae4f6362b0b40f8726f014cb44d6dc46ab9c892/tests/test_ai_mihomo_version_only_readonly.rb)覆盖：`-v`写stdout/stderr、格式不识别、完全无输出、命令不能启动、被检查子进程挂起须及时清理。第一次CI中的测试stderr重定向写法有误，已修复并重新运行全部回归。
- [固定Git提交 `fae4f6362b0b40f8726f014cb44d6dc46ab9c892`](https://github.com/Kimbersy/openclash/commit/fae4f6362b0b40f8726f014cb44d6dc46ab9c892) / [GitHub Actions #43569940220](https://github.com/Kimbersy/openclash/actions/runs/43569940220) `completed/success`，**包括精简Ruby依赖门禁、官方Mihomo隔离监听器合成原生 `-t`、旧全地区动态组和三端非AI冻结回归**。这仍是仓库CI，不是家中版本诊断回执。

## 唯一下一步（最短一次实机操作）

**无需重做15:02端口及结构检查。** 用户在家中 iStoreOS TTYD 运行以下固定SHA单条命令，得到匿名 `MIHOMO_VERSION_RESULT` 和 `MIHOMO_VERSION`，回传结果；如果失败只针对该原因调查：

```sh
( umask 077; f="$(mktemp /tmp/ai_ver_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/fae4f6362b0b40f8726f014cb44d6dc46ab9c892/scripts/ai_mihomo_version_only_readonly.rb"; then ruby "$f" || echo "MIHOMO_VERSION_RESULT=HOLD_SCRIPT_RUNTIME PRODUCTION_WRITES=NONE"; else echo "MIHOMO_VERSION_RESULT=HOLD_DOWNLOAD_UNAVAILABLE PRODUCTION_WRITES=NONE"; fi; rm -f "$f" )
```

- `VERSION_IDENTIFIED`：拿到实际版本后核对`listeners[].proxy`支持，再进入**受保护配置副本**的正式核心`-t`（不是直接装新Listener）。
- `HOLD_VERSION_EMPTY_OUTPUT`：内核`-v`标准及错误流都无内容，需改验证方式，不再盲改选项。
- `HOLD_VERSION_FORMAT_UNRECOGNIZED`：`-v`返回内容但与`X.Y.Z`不匹配；只探索安全的版本元数据，不向公共仓库粘贴原始输出。
- `HOLD_VERSION_TIMEOUT`/`HOLD_VERSION_EXEC_UNAVAILABLE`/`HOLD_VERSION_RUBY_RUNTIME`：分别处理时限、子程序不可启动、精简Ruby核心功能异常；不得据此声称内核不能正常代理。
- 未获用户明确生产变更许可之前，**不新建监听器、不发送Controller PUT、不修改🤖 AI/non-AI组、不重启内核、不启用自动切换**。全部有效订阅节点、各AI独立资格、动态真实地区分组、订阅成功后增量刷新和稳态自动主备，仍为P0最终验收目标。

**本轮已完成：15:02真实验收已保存 + 版本单点诊断源码/CI完成。未完成：最新脚本在家中执行及实际版本结果。**
