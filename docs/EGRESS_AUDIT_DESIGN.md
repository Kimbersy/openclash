# AI 节点真实出口核验：候选方案（尚未部署）

更新日期：2026-11-11。所有新增代码只在候选分支，未改主分支、设备和现有订阅；尚无实际机场节点的出口核验结果。

## 为什么需要单独检测

原 Clash-Li.ini 仅凭机场节点名称正则筛选台湾、日本、美国等地区；gstatic generate_204 只检查连通性，并不能确认真正的出口 IP。标称台湾、实际香港落地的节点仍可能进入台湾组。

现有架构：Clash-Li.ini 为策略与规则源；scripts/generate_android.py 与 scripts/generate_shadowrocket.py 生成 Android/Mihomo 与 Shadowrocket 配置。Android 模板的 __AIRPORT_URL__ 由现有 Cloudflare Worker 注入。公开仓库不应该持有机场订阅或凭据。

## 已提交的两个独立组件

1. scripts/audit_egress.py：由可信的私有运行器为每个机场节点提供唯一的本地 HTTP CONNECT 代理端口。本脚本经该端口访问 ipinfo.io 与 ipapi.co 的 HTTPS IP 回显服务，观察实际出口 IP 和国家代码。两个来源的 IP、国家均一致，且节点名称唯一指向该国家，才列为 match。地区不一致列 mismatch；来源互相矛盾列 inconsistent；失败或名称不明确列 unknown。脚本不下载机场订阅，也不创建各节点的本地代理端口。
2. scripts/render_verified_candidate.py：从不超过 6 小时的私有报告提取核验匹配的节点，仅新增“🧭核验🇹🇼台湾”等候选组，追加在 AI 策略现有选项后；调用原有两个生成器形成 Mihomo 和 Shadowrocket 的私有完整候选配置。不会自动选择新组，也不会改 Disney+、普通网页、GitHub 等分流规则。

重要兼容点：原 Android 生成器会清除某些正则的开头 ^ 和结尾 $；本候选使用 (?:^(?:节点1|节点2)$) 形式包裹精确名称，防止清理后重新成为模糊名称匹配。测试必须覆盖真实两个生成器。

## AI 稳态候选组（2026-11-12，未安装）

- 原有 `🤖 AI` select 选项与顺序、台湾原有 `🇹🇼台湾-自动`、YouTube / Disney+ 等规则不改变。只在当前私有候选中追加可手动选择的组。
- 只有真实出口 IP 与国家经 ipinfo、ipapi 两源一致验证，且台湾节点至少两个，才追加 `🛡️AI 稳态🇹🇼台湾`：标准 fallback，精确筛选已验证的 TW 节点；探测 `https://www.gstatic.com/generate_204`，间隔 600 秒、超时 10 秒（原台湾自动组为 180 秒、5 秒）。单节点不能假称具备自动容灾。
- fallback 仍可能在故障和恢复时更换线路，**不保证 AI 长连接不中断**，也不提供冷却时间/防抖算法。`gstatic 204` 只能测连通性，不能证明 Gemini/ChatGPT 地区资格。用户需要主动在 AI 选择器中试用这个新选项。
- 同一 `Clash-Li.ini` 源同时生成 Android/Mihomo、Shadowrocket 候选配置，已用两套原有转换器测试。正式订阅、Worker、设备尚未变化。
- 参考 Mihomo 官方组字段 https://wiki.metacubex.one/en/config/proxy-groups/ ，Subconverter group INI 语法 https://github.com/tindy2013/subconverter/blob/master/README-cn.md 。

## 不切换现有 AI 节点的真实出口检测准备（2026-11-12，未实机）

- 新增 `scripts/prepare_isolated_audit.py`：从**仅本地保存**的机场 `proxies:` YAML 和 JSON 精确节点名称列表生成一个**独立 Mihomo 进程**使用的最小配置，并产生现有 `audit_egress.py` 所需的逐节点 loopback HTTP 端口映射。
- 监听仅为 `127.0.0.1:17801+`；每个入站指定一个真实代理节点，`MATCH,REJECT` 兜底，防止不受控直连。不会启用 TUN、透明代理、LAN 服务或外部控制器；不会启动或修改正在使用的 OpenClash。
- 仅选取 1–32 个节点、拒绝保留节点名/重复名/无效端口，预查端口占用；私有配置和名称只在指定的**非公开 Git 仓库外**的目录存放（目录 0700、文件 0600）。生成的 Mihomo 配置包含私密节点凭据，严禁提交到 GitHub、发送聊天或公开日志。
- 安全流程：在用户可信设备/路由器的独立运行环境安装 PyYAML==6.0.2，私有准备 `provider-nodes.yaml` 和 `selected-names.json`（例如 `["台湾01", "台湾02"]`），运行准备器生成 `isolated-mihomo.yaml`、`egress-inventory.json`；再用 `mihomo -t -d <private_dir> -f <private_yaml>` **检查配置**，确认后在单独进程运行 Mihomo，再执行 `audit_egress.py` 与 `render_verified_candidate.py`。
- 用户目前只有手机，**不要求现在在手机运行任何命令**。以上程序的输出安全与业务兼容目前只完成离线 CI；没有执行真实机场节点访问，没有修改路由器。测试时优先以家里电信出口为起点，不能用 GitHub 美国托管环境等同家庭路径。
- 官方依据：https://wiki.metacubex.one/en/config/inbound/listeners/ （listener 支持 `proxy` 指定出站节点）；配置检查仅保证可解析，不等于真实节点可用。
## 私有使用示例（仅限已准备好逐节点本地代理端口）

私有 JSON 结构：

    {
      "schema_version": 1,
      "nodes": [
        {"name": "台湾01", "proxy_url": "http://127.0.0.1:7801"},
        {"name": "台湾02", "proxy_url": "http://127.0.0.1:7802"}
      ]
    }

运行：

    python3 scripts/audit_egress.py --inventory /private/nodes.json --report /private/egress-report.json
    python3 scripts/render_verified_candidate.py --report /private/egress-report.json --source-ini Clash-Li.ini --output-dir /private/verified-client-candidates
    python3 -m unittest discover -s tests -p 'test_*.py' -v

输出目录为私有地址，含 Clash-Li.verified-candidate.ini、Clash-Meta-Android.verified-candidate.yaml、Shadowrocket.verified-candidate.conf。源代码和发布的 generated 目录保持不变。

**不得将机场订阅 URL、节点密码、完整出口检测报告、私有生成配置提交到本公开仓库**。报告可能含节点名和真实出口 IP。敏感数据应由私有 runner/Worker 保管，在权限控制下交给客户端。GitHub Actions 常规公开构建无需且不应取得这些密钥。

## 范围限制

- 本轮没有机场节点的真实代理端口/可安全访问的私有订阅，因此没有做真实 IP 检测。
- 当前只比较两个 IP 回显提供者的观察；未独立验证 IPv6、目标站点特定出口、服务器物理机房位置，不能代表 AI 服务地区资格。
- 使用共享候选配置仍要求真实设备和 Cloudflare Worker 的节点名称一致，并由私有渠道分发生成物；此链路尚未验收。
- 出口地理真实性和“AI 会话不频繁自动切换”是不同问题。后者仍需保守主备切换策略及实机验证。
- 不能保证账号平台接受某个出口，实际使用仍必须符合服务所在地区和账号条款。

## 回归与发布条件

生成候选的自动测试通过后，仍需测试 iStoreOS/OpenClash、Android/Mihomo、Shadowrocket 实际解析及切换；验证台湾标签/香港落地被排除、失败和过期时不错误归组、普通网页/YouTube/Disney+ 分流不退步；记录固定提交及实机结果后才可评估合并主分支。

## 唯一下一步

候选分支代码和自动测试都可读且通过后，确认当前 Cloudflare Worker/私有机场订阅可怎样安全交给独立测试进程，创建小批真实节点的本地独立代理端口并逐个检测；未获得真实报告前，不发布自动白名单，不改设备。
