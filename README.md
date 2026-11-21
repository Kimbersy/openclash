# Kimbersy/openclash — 家庭 Clash 公共规则、模板与工具

> **个人维护的公开配置/生成源码仓库，并非 OpenClash（软件本身）的官方上游仓库。** 为既有家庭 OpenClash/Mihomo、客户端模板、转换器工具提供可固定 Git commit 引用的源文件。本仓库的任何文件或 CI 通过**不等于**已经部署到路由器/手机/Cloudflare。

## 统一项目接续入口

**[家庭 IT 私有 Clash 项目总入口](https://github.com/Kimbersy/home-it-index/blob/main/docs/clash/README.md)**（访问需要授权）负责梳理 OpenClash、ClashMate、clash-home、AnyTLS、Cloudflare Worker 和实机回执之间的关系。

- [OpenClash / AI 主线当前任务](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_CURRENT_WORK.md)（私有）：完整原目标、当前状态、固定 Git 提交及设备验收。
- [AI P0 完整验收契约](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_AI_P0_ACCEPTANCE_CONTRACT.md)（私有）：全节点发现、独立业务资格、按真实出口地区分组、增量更新与稳定自动切换；未全体验收前不得宣称完成。
- [clash-config-worker](https://github.com/Kimbersy/clash-config-worker)（私有）：现役 Cloudflare Worker 的源码、绑定、隔离预览及手动分阶段发布门禁；**不由此公共仓库自动部署**。
- [GitHub 通用维护基准](https://github.com/Kimbersy/home-it-index/blob/main/GITHUB_PROJECT_MAINTENANCE_BASELINE.md)（私有）：固定提交证明源码、原实机回执证明业务，禁止重复安装已验项目。

## 本仓库文件分工

| 路径 | 用途 |
|---|---|
| [Clash-Li.ini](Clash-Li.ini) | 现役规则转换模板；修改前须守住已有策略组与客户端行为 |
| [generated/Clash-Meta-Android.template.yaml](generated/Clash-Meta-Android.template.yaml) | Android/Mihomo **公开占位模板**，真实订阅 URL 由独立私有 Worker 的 KV 等运行路径处理 |
| [generated/Shadowrocket.conf](generated/Shadowrocket.conf) | 由生成脚本产生的 iOS 配置，跟 Worker 的 Android `/config` 不同 |
| [scripts](scripts) | 通用 Android/Shadowrocket 配置生成器继续公开；家庭设备操作/发布脚本在本分支仅保留**不可执行的安全占位**，原文已迁入私有索引 |
| [list](list) | 规则列表 |
| [docs](docs) | 历史专属家庭网络/AI 运维文档仅保留迁移说明，完整内容已迁入私有索引；以带时间的真实验收为准 |
| [.github/workflows](.github/workflows) | CI 生成配置或手工镜像转运；不直接等同于 iStoreOS/Cloudflare 生产发布 |

**已知业务结果**：2026-11-21 ClashMate AnyTLS 连接由用户确认正常；原有服务端离线缓存刷新及 A01 SNI 已验。此事项结案，与更大范围的 AI P0 自动节点管理（仍未最终验收）分别维护。

## 本次安全归档（2026-11-22）

已将 5 份家庭专属技术文档、22 个历史设备操作脚本及 1 个配套测试原样保存至私有 [Clash 安全归档](https://github.com/Kimbersy/home-it-index/tree/main/docs/clash/private-archive)（需授权）；公开 main 上的原路径仅保留说明和拒绝执行的占位脚本。**不要将历史旧版本的脚本作为当前安装入口**。Git 旧历史提交仍可公开访问，不能误称已消除历史暴露；正式设备/订阅运行不受本次仓库源码归档影响。当前生成配置与公开 Raw 分发路径保持不变。

## Public / Private 边界

本仓库当前为 **Public**。已有设备、客户端或 Worker 使用这里的公开 Raw 文件或固定 commit 一键命令；**不得为“整理”直接改为 Private**，否则未经认证的 Raw 读取可能失效。任何变更可见性须先核对客户端/自动任务依赖、准备替代分发并另行批准。

**绝不在这里提交**真实机场订阅 URL、认证凭据、完整节点连接定义、Cloudflare KV 值/Token、真实用户连接日志、详细家庭网络拓扑或其他私人运行回执；必要的运维和业务证据放在上述私有索引/私有 Worker 仓库。过去公开技术文档可能包含局部家庭网络信息，不应把公开代码视为完整安全审计通过；历史已发表内容也不会因为后来切换 private 就自动从其他副本消失。

参考本仓库 [AGENTS.md](AGENTS.md) 执行固定源码、最小变更、审查与安装前门禁。
