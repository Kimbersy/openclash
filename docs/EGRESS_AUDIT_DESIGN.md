# AI 节点真实出口核验：候选方案（尚未部署）

更新日期：2026-11-11。所有新增代码只在候选分支，未改主分支、设备和现有订阅；尚无实际机场节点的出口核验结果。

## 为什么需要单独检测

原 Clash-Li.ini 仅凭机场节点名称正则筛选台湾、日本、美国等地区；gstatic generate_204 只检查连通性，并不能确认真正的出口 IP。标称台湾、实际香港落地的节点仍可能进入台湾组。

现有架构：Clash-Li.ini 为策略与规则源；scripts/generate_android.py 与 scripts/generate_shadowrocket.py 生成 Android/Mihomo 与 Shadowrocket 配置。Android 模板的 __AIRPORT_URL__ 由现有 Cloudflare Worker 注入。公开仓库不应该持有机场订阅或凭据。

## 已提交的两个独立组件

1. scripts/audit_egress.py：由可信的私有运行器为每个机场节点提供唯一的本地 HTTP CONNECT 代理端口。本脚本经该端口访问 ipinfo.io 与 ipapi.co 的 HTTPS IP 回显服务，观察实际出口 IP 和国家代码。两个来源的 IP、国家均一致，且节点名称唯一指向该国家，才列为 match。地区不一致列 mismatch；来源互相矛盾列 inconsistent；失败或名称不明确列 unknown。脚本不下载机场订阅，也不创建各节点的本地代理端口。
2. scripts/render_verified_candidate.py：从不超过 6 小时的私有报告提取核验匹配的节点，仅新增“🧭核验🇹🇼台湾”等候选组，追加在 AI 策略现有选项后；调用原有两个生成器形成 Mihomo 和 Shadowrocket 的私有完整候选配置。不会自动选择新组，也不会改 Disney+、普通网页、GitHub 等分流规则。

重要兼容点：原 Android 生成器会清除某些正则的开头 ^ 和结尾 $；本候选使用 (?:^(?:节点1|节点2)$) 形式包裹精确名称，防止清理后重新成为模糊名称匹配。测试必须覆盖真实两个生成器。

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
