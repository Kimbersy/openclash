# 家庭 iStoreOS 单节点出口测试：安全的准备阶段（未启动核心）

更新：2026-11-12。**此流程只生成本地文件，不安装任何服务、不重启或更改现有 OpenClash，不影响原有 AI 组。**

## 已确认的事实与用途

- iStoreOS 已存在 Ruby/Psych、curl 和可执行的 Mihomo core；当前设备约 1100 MiB `MemAvailable`、`/tmp` 约 929 MB 可用（均为此前实机时点的状态，不能保证未来资源不变）。
- UCI 当前活动的机场订阅配置在路由器私有目录内。2026-11-12 17:52 的动态盘点快照显示 58 条**标称标签**：AU6、CA1、DE1、FR1、GB1、HK6、JP8、KR6、SG10、TW7、UNKNOWN7、US4。这不是各出口国家的真实观测结果，不能按此判断 NotebookLM/ChatGPT/Gemini 可用性。
- [`scripts/prepare_local_probe.rb`](../scripts/prepare_local_probe.rb) 是 Ruby/Psych 原生预处理工具；支持 HK、TW、JP、SG、US、KR、DE、GB、FR、CA、AU、NL、UNKNOWN、AMBIGUOUS 等标签选样，不固定实际节点数；默认选择指定标签的第 1 条，仅作为实验样本。
- 工具从 UCI 读取当前活动的**本机私有**完整 YAML，使用 `Psych.safe_load`，要求名字唯一、无额外 dialer-proxy 引用。只提取一个节点定义，写到权限 0700 的 `/tmp/openclash-probe-*/isolated.yaml`（0600）与源文件快照 `snapshot.json`（0600）。读取前后再检查原始订阅字节，遇刷新冲突则失败并删除未完成临时目录。**节点密码只存本机私有文件，不发送到 GitHub/聊天。**
- 配置中只有 1 个监听 `127.0.0.1:17881`、出站固定为所选单节点；`tun` 禁用，顶层端口为0、控制口空、LAN共享关闭，`MATCH,REJECT` 兜底。**只生成文件，未启动 Mihomo、未暴露任何局域网代理端口、未修改当前系统转发/DNS/规则/AI选择。**
- `--verify <PREPARED_PRIVATE_DIR>` 只检查生成批次时的 SHA256/字节数是否仍与当前活动订阅一致；机场更新后返回失败，不允许用旧的节点定义直接继续检测。

## 第一阶段（唯一当前实机步骤）：只准备，不启动

**从经过 CI 验证的固定 Git 提交获取脚本：**

```sh
umask 077
curl -fsSL --max-time 20 \
  'https://raw.githubusercontent.com/Kimbersy/openclash/c788706367d3122e1f6b6e94d8d1a5b3afbe8183/scripts/prepare_local_probe.rb' \
  -o /tmp/prepare-local-probe.rb &&
ruby /tmp/prepare-local-probe.rb HK 1
```

脚本回执仅有 `PREPARED_PRIVATE_DIR=/tmp/openclash-probe-...`、`CURRENT_NODE_COUNT`、`REGION`、`CANDIDATES`、`SAMPLE`、`LISTEN=127.0.0.1:17881 STARTED=NO LIVE_CONFIG_CHANGED=NO`；或 `PRIVATE_PROBE_CHECK_FAILED`。**不得 `cat` 生成的 `isolated.yaml` 或 `snapshot.json`，不要发送任何实际节点或机场信息。** 如果脚本无法从 GitHub 获取，不要换成不明来源的镜像脚本，应先停止并记录。

为什么先从 HK 选 1 条？只是一个**对照样本**，用户反馈部分香港线路 ChatGPT 可用、NotebookLM 可能不可用；它并非第一优先地区或最终规则，接下来还应分批验证 JP/SG/TW/UNKNOWN 等，按照实际出口 IP 和每项 AI 应用的真实功能决定用途。不能凭 HK 标签断言服务被限制。

## 后续阶段，不在此步执行

- 第二步：检查配置有效性与独立端口，核对**私有数据没有泄漏到日志**、系统剩余内存与订阅快照仍然最新；运行 `clash_meta -t -d <PRIVATE_DIR> -f <PRIVATE_DIR>/isolated.yaml` 时可能写入所选私有目录，**不是纯只读**；必须使用独立目录，严禁指向 OpenClash 正在使用的 `/etc/openclash` 数据目录。
- 第三步：评估资源占用与最短存活时间后才单独启动**受控的第二个 Mihomo**，通过仅本机 `curl --proxy http://127.0.0.1:17881` 获取两家 IP 回显，再核验国家一致性。必须确保关闭与清理，不把任何 IP 结果当成 AI 平台可用性证明。
- 第四步：按 ChatGPT/NotebookLM/Gemini 逐一实机验证、收集切换/断流数据和最新订阅快照，决定是否产生候选分流；现有 YouTube/Disney+ 和用户正在使用的 AI 选择保持不变。

## 证据与限制

- 基线/订阅动态机制：[方案](EGRESS_AUDIT_DESIGN.md)；[工程当前任务](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_CURRENT_WORK.md)。
- GitHub Actions [#43196657859](https://github.com/Kimbersy/openclash/actions/runs/43196657859) 已对**固定 Git 源 `c788706367d3122e1f6b6e94d8d1a5b3afbe8183`**运行 Ruby 语法与 46 项模拟/跨端测试 `success`，其中单节点脚本只使用合成假的节点凭据。
- 未有真实机场出口 IP、各 AI 服务资格、手机端业务或者 OpenClash 第二核心安装的验收回执。任何真实节点数量和服务资格都必须以未来实际采样为准。
- Mihomo 官方文档：[`listeners.proxy`](https://wiki.metacubex.one/en/config/inbound/listeners/) 可指定一个独立出站节点；[入站安全](https://wiki.metacubex.one/en/config/inbound/) 强调 HTTP/SOCKS 监听不能暴露到公网。
