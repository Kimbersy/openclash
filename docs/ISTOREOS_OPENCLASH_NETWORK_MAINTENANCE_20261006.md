# iStoreOS / OpenClash 网络维护验收记录（2026-10-06）

> 2026-11-20 从既有实机排障对话同步入库。本文记录 2026-09-30 至 2026-10-06 的家庭 iStoreOS/OpenClash 维护结果；这是运行维护证据，不覆盖 OpenClash AI P0 工程主线。

## 目标与验收

目标：解释连续多晚约 21 点后的 OpenClash 断联、验证 Fail-Open 能恢复业务、定位主要诱因，并修复 VLAN30 访客网可越权访问管理/Docker 服务的问题。

验收口径：

- OpenClash 故障发生时 Fail-Open 能切直连并自动恢复；
- 找到故障前可复现的资源/连接异常及进程级证据；
- 采取单一变量停用后连续观察，不把相关性误写成绝对因果；
- VLAN30 保持正常上网，同时禁止访问路由器管理、Zashboard、Docker/青龙及其他内网设备；
- 不为清理“看起来异常但未证明有害”的 WAN zone 冒险改动现网。

## 一、连续晚间故障与 Fail-Open

已确认的晚间故障：

- 2026-09-30：21:25:46 首次 BROKEN，21:26:16 确认故障，21:30:39 自动恢复，21:30:49 HEALTHY。
- 2026-10-01：21:30:00 BROKEN，21:30:15 短暂 HEALTHY，21:30:30 再次 BROKEN，21:31:00 Fail-Open；21:35:25 恢复，21:35:35 HEALTHY。
- 2026-10-02：21:34:41 BROKEN，21:35:11 确认故障，21:35:38 Fail-Open 生效，21:39:32 恢复，21:39:42 HEALTHY。
- 2026-10-03：21:39:00 BROKEN，21:39:31 确认故障，21:39:57 Fail-Open 生效，21:43:53 恢复，21:44:03 HEALTHY。

这些记录证明 Fail-Open 机制本身完成了预期容灾：故障时切直连，随后自动回切 OpenClash。

## 二、排除项

本轮已检查并不再作为首要方向重复排查：

- 21 点故障不是订阅自动刷新直接触发；watch-clash-li 在 2026-10-01 21:30 记录的是 GitHub check failed / skipped，refresh.log 没有 21:30 刷新。
- 旧 eth1/r8169 链路抖动真实存在，但按 uptime 换算发生在更早日期，与 9/30–10/03 晚间故障不重合。
- Clash 自身进程 GID=65534，与既有防火墙绕过规则一致，没有证据支持“Clash 出口被自身透明代理再次循环”的假设。
- 青龙长期 unhealthy 是既有现象，不能单独解释本次晚间连接暴涨。
- 原先的 cron、常驻 Cloudflare/speedtest 进程等已查过，没有发现与每晚故障直接对应的固定任务。

## 三、2026-10-02 现场连接与内存证据

故障窗口内，conntrack 与内存出现突变：

| 时间 | nf_conntrack_count | MemAvailable |
|---|---:|---:|
| 21:34:23 | 2,144 | 约 1.21 GiB |
| 21:34:43 | 13,743 | 约 711 MiB |
| 21:35:07 | 23,637 | 约 586 MiB |
| 21:38:59 | 2,151 | 约 1.17 GiB |

21:35 左右可见约 2.4 万条路由器侧 443 连接，目标涉及约 4,900 个不同 IP，目标高度集中于 Cloudflare 地址段；其中约 1.96 万条被本机透明代理重定向到 Clash 7892，超过 1.1 万条处于 SYN_SENT。

这说明 OpenClash 被判 BROKEN 前后，系统已经处于连接风暴和明显内存压力中。

## 四、2026-10-03 PID 触发捕获：iStoreEnhance / KSpeeder

为避免继续只看 IP，部署一次性“conntrack >= 6500 即抓 PID”的轻量采集。

2026-10-03 21:38:33，故障前约 27 秒，采集到：

- conntrack = 6,536；
- iStoreEnhance：200 条 SYN_SENT；
- clash：14 条 SYN_SENT。

随后 21:39:00 Failover 记录 state=BROKEN。

iStoreOS 页面进一步确认 KSpeeder 正在运行，管理端口 5003、服务端口 5443，缓存路径为 `/mnt/sata1-4/Configs/iStoreEnhance`，与进程名 iStoreEnhance 对应。

### 结论边界

当前证据支持：

**KSpeeder / iStoreEnhance 是本次连续晚间故障的高置信主要诱因。**

但没有做受控的“重新启用并复现”破坏性试验，因此不写成 100% 因果证明。

## 五、停用对照

2026-10-03 21:58 取消 KSpeeder“启用”并保存应用，页面确认：

`The KSpeeder service is not running.`

保持其他 OpenClash/DNS/Failover 配置不变：

- 2026-10-04 晚：Failover 监控正常，KSpeeder 未运行，21 点未记录 BROKEN / Fail-Open。
- 2026-10-05 晚：KSpeeder 仍停止，没有此前同类 21 点晚间故障。凌晨 01:00 出现一次约 9 秒 Fail-Open，属于另一个时间窗口，不与本次晚间故障等同。

因此形成“开启时连续 4 晚故障、关闭后连续 2 晚无同类故障”的对照证据。

### 运行基线

- KSpeeder / iStoreEnhance：保持关闭。
- OpenClash Failover：长期保留。
- Failover 脚本中的 `BROKEN detail: core/utun/dns` 诊断代码：保留。
- 临时 `capture-2130` / `capture-pid` cron 与采集脚本：已清理。
- 不再重复此前已经排除的同类调查，除非出现新的现象或新证据。

### 设备侧关键证据留存

仍保留在路由器：

- `/mnt/sata1-4/network-watch/incident-20261002.tar.gz`（约 1.6 MiB）
- `/mnt/sata1-4/network-watch/pid-on-burst-20261003.log`（约 11.8 KiB）

这些是设备侧运行证据，不等同于 Git 源码提交，也未把原始连接明细上传进仓库。

## 六、VLAN30 访客网隔离漏洞

### 原问题

Guest 接口 `10.68.30.0/24` 属于 `lan` firewall zone，而 lan zone 为 INPUT/FORWARD ACCEPT；同时存在 `lan_to_docker`。

原有：

- `Guest_Block_Intranet`：只阻止 Guest 到 10.68.10/20/40/50 网段；
- `Guest_Block_Admin`：只阻止 TCP 60080/60443/60022。

因此 VLAN30 虽然不能访问 HA 等其他内网设备，却仍可以访问：

- Zashboard / Clash Controller：9090；
- 青龙：5700；
- 其他发布到 0.0.0.0 的 Docker 服务。

### 已执行修复

修改前备份：

`/etc/config/firewall.bak-guestfix-20261006`

新增持久 UCI 规则：

- `Guest_Allow_DNS`：VLAN30 -> 本机 TCP/UDP 53；
- `Guest_Allow_DHCP`：VLAN30 -> 本机 UDP 67；
- `Guest_Allow_OpenClash`：VLAN30 -> 本机 TCP/UDP 7892,7893；
- `Guest_Block_Router`：VLAN30 -> 10.0.0.0/8，all，REJECT；
- `Guest_Block_Docker`：VLAN30 -> docker zone，all，REJECT。

随后 `uci commit firewall` 并 reload。

### 用户实机验收

用户明确反馈“已经正常隔离了”。

当前验收：

- VLAN30 普通互联网：正常；
- 路由器管理：不可访问；
- Zashboard：不可访问；
- 青龙/Docker 服务：不可访问；
- HA/其他内网设备：不可访问。

原有 `Guest_Block_Intranet` 和 `Guest_Block_Admin` 暂保留，作为额外防护，不在本轮继续重构。

## 七、WAN zone / br-lan 双归属：确认但不改

审计发现 firewall `wan` zone：

- 也包含 `lan` / `lan6`；
- input/output/forward = ACCEPT；
- masq = 1；
- 运行态 `br-lan` 同时命中 zone_lan 和 zone_wan。

实际拓扑：

- 默认路由：`default via 10.68.10.1 dev br-lan proto static`；
- eth0 无 IPv4；
- 这是单臂/旁路由式出网。

运行态计数：

- `zone_wan_postrouting` MASQUERADE：0；
- `zone_wan_forward`：0；
- `zone_wan_input`：仅少量包（当时 13 packets / 2473 bytes）；
- `zone_lan_*` 承担大量真实 VLAN20/30/50 业务；
- `zone_lan_postrouting` 有实际 MASQUERADE 计数。

结论：

**wan zone 更像历史/冗余结构，而非当前故障点。**

因为它仍被 WireGuard / Docker / OpenClash 等现有配置引用，当前不删除、不改归属，不为“结构更漂亮”冒业务风险。未来只有在专门做网络架构重构时再处理。

## 八、维护状态与后续

本维护事项当前为 **CLOSED / MONITOR**：

- KSpeeder 保持关闭；
- VLAN30 隔离已验收；
- WAN zone 冗余记录留存但不改；
- 现有 OpenClash AI P0 工程主线不受本维护记录影响。

如未来再次出现同类 21 点晚间 BROKEN：

1. 先确认 `iStoreEnhance` 是否仍未运行；
2. 先看现有 Failover / BROKEN detail；
3. 复用 2026-10-02/03 的设备侧证据，不重复从订阅刷新、旧 r8169 抖动、固定 cron 等已排除方向重新开始；
4. 只有出现新的进程级或链路级证据，再开新调查。
