# 路由器P0：三个AI真实业务“同出口”验收及NotebookLM优先门禁（2026-11-14）

**状态：公共规则静态复核和纯离线故障回归已通过；家中路由器真实浏览器业务尚无合格回执。** 这份规范是在全订阅/地区/订阅增量P0主线上的一道业务发布前置门，不能以某页面HTTP 200、应用入口到达或人工填表为上线许可。

## 目标：必须先真正能用，再入池/接替

- **ChatGPT**：同一浏览器路由出口，登录态有效、生成回答及连续/流式输出确实完成；区分账号地区限制/风控、系统服务故障、真实线路失败。
- **Gemini**：Google账号有效、模型确实生成回答；登录、APP请求经同一个用户选定AI节点出口。
- **NotebookLM（2026 Google文档亦称Gemini Notebook）重点**：经同一个选定AI节点，实际Google登录、进入个人笔记本、从无敏感的样例文本导入来源、根据来源提出问题并得到答案、引用可点开核对所上传来源。**登录页、首页/宣传页、现成笔记本URL、单一HTTP200都不等于本轮达标。** 需要看来源导入和引用才算核心业务实用。

## 已核实的目前配置和官方产品流程

- 公共固定`list/AI.list`现已具有：`DOMAIN,accounts.google.com`、`DOMAIN-SUFFIX,gemini.google.com`、`DOMAIN-SUFFIX,chatgpt.com`、`DOMAIN-SUFFIX,openai.com`、`DOMAIN-SUFFIX,notebook.google.com`、`DOMAIN-SUFFIX,notebooklm.google.com`、`DOMAIN,notebooklm-pa.googleapis.com`、`DOMAIN,notebooklm.googleapis.com`和`DOMAIN,contribution.usercontent.google.com`。公共`Clash-Li.ini`的`ruleset=🤖 AI`位于`🌍 国外`/国内兜底规则前；现有父组为手工`select`。
- **不要为NotebookLM贸然加入**`DOMAIN-SUFFIX,google.com`、`DOMAIN-SUFFIX,googleapis.com`、`DOMAIN-SUFFIX,gstatic.com`，也不把宣传页`notebook.google`当应用主机。现有公共AI规则同时作用三端，涉及普通Google/非AI；增加未知依赖**先取真实路由命中证据，再只在路由器本地独立覆盖层试验**，通过非AI零差异后才考虑发布。
- Google官方目前在[个人版Notebook入门/添加来源](https://support.google.com/gemininotebook/answer/16215270?hl=en)支持粘贴文本、文件导入；[Notebook问答](https://support.google.com/gemininotebook/answer/16179559)说明回答可根据来源引用；[Google帮助](https://support.google.com/gemininotebook/answer/16164461?hl=zh-Hans)还强调实际国家/年龄/账号条件，[常见问题](https://support.google.com/gemininotebook/answer/16269187?hl=zh-Hans)指出导入上限与Workspace管理权限可能影响体验。Notebook实际应用入口示例`notebook.google.com`，旧入口`notebooklm.google.com`仍见Google官方链接；不能因营销重定向就自动把域名改到`notebook.google`。
- 社区[NotebookLM Python客户端故障讨论#2175](https://github.com/teng-lin/notebooklm-py/issues/2175)曾观察`location=unsupported`区域/反滥用跳转，原因可能包含代理出口、浏览器特征和账号地区条件，**不是仅凭重定向就能确定某机场节点必定不可用**。官方Google账号年龄/地区/工作区权限因素也须分类。此前用户01/05/08–11隔离脚本在少数入口观察到`APP_ENTRY_CANDIDATE_NOT_VERIFIED`；全部真实业务资格仍`UNKNOWN`。

## 离线源码和合成测试现状

新增[纯离线浏览器回执审查`scripts/ai_three_service_browser_flow_gate.py`](https://github.com/Kimbersy/openclash/blob/ac8e2afc64a3102319186d5c579bd5c87402362a/scripts/ai_three_service_browser_flow_gate.py)、[合成回归`tests/test_ai_three_service_browser_flow_gate.py`](https://github.com/Kimbersy/openclash/blob/ac8e2afc64a3102319186d5c579bd5c87402362a/tests/test_ai_three_service_browser_flow_gate.py)：

- [x] 三平台业务动作的模拟回执必须含正确服务、完整连接指纹、有效时间、同一匿名会话；所观察`app`/导入/回答的路线都属于`🤖 AI`并标记相同出口，不能跳其他地区/国外组；登录发生重定向时Google验证需经过`accounts.google.com`。
- [x] NotebookLM必须有真实登录态、工作区、来源导入、来源问答和引用核对；`location=unsupported`/宣传页、非应用host、未知跳转、403/429、网络失败、缺登录路由、不同出口或只有HTTP200全拒绝。
- [x] 所有返回结果只含匿名固定决策，**即便合成流程全通过也永远`business_verified=false`、`allow_switch=false`、`live_writes=false`**；它仅验证证据结构，**不能独立认证声明真实业务已完成**。必须另有实际浏览器/官方账号操作、路由器连接回执、来源有效性和操作者确认。
- [x] 保持已有`AI.list`、`Clash-Li.ini`、Android、Shadowrocket、Worker、所有非AI规则**不写入**；现有NotebookLM`ai_network_batch_once.sh`的落地页/登录/应用入口分类安全回归继续保留。
- 固定源码提交[ac8e2afc64a3102319186d5c579bd5c87402362a](https://github.com/Kimbersy/openclash/commit/ac8e2afc64a3102319186d5c579bd5c87402362a)，[GitHub Actions #43545392540](https://github.com/Kimbersy/openclash/actions/runs/43545392540) `completed/success`（包含新三平台路由/NotebookLM导入回归、此前全订阅全地区增量回归与三端非AI冻结回归）。**这是源码/CI成功，不是路由器真实业务验收。**

## 真实路由器业务最小验收（仍待执行）

在用户既有家庭网络下，**保持正常OpenClash配置和人工稳定选中的现有AI节点**，不新开第二常驻核心、不开自动切线；至多先验一个当前主节点及一个备节点，试点小不限制最终全订阅发现范围：

1. 在真实Chrome/浏览器同一窗口，固定人工AI节点，不执行新的自动选择。只以私有受保护的路由器Mihomo连接记录勾稽`🤖 AI`和同一叶节点/出口、选中线路；**不将浏览器Cookie、账号、完整节点/IP、Notebook内容、Google文件、原始URL日志上交公共Git或聊天**。
2. ChatGPT：实际登录，发一条无隐私普通对话，确认回复和流式完成。若OpenAI账号/地区限制需区别于网络节点不通，参考[OpenAI登录排查](https://help.openai.com/en/articles/7426629-why-cant-i-log-in-to-chatgpt)及[支持区域](https://help.openai.com/en/articles/7947663-chatgpt-supported-countries)。
3. Gemini：同一人工出口下Google账号进入`gemini.google.com`并获得一次真实回答；Google登录跳转的`accounts.google.com`若发生应仍命中AI组，不能与NotebookLM同会话拆为不同行政地区出口。
4. **NotebookLM：建议复制以下虚构文本当作测试来源**（不提供私人资料、不必上传已归档工作文件）：
   > The fictional North Harbor library held a reading workshop on Tuesday. Students arrived at nine o'clock and read a story about a hidden garden. After a short break, they wrote a summary in pairs. Each pair explained the main idea of the story and described one important detail. At the end of the workshop, the teacher collected the summaries and thanked the students for their work. The workshop finished before noon.
   
   登录个人版Notebook，建立/打开测试笔记本、用**粘贴文本**添加此来源，确认来源实际出现在列表并可读取，问“**What did the students do after the break?**”，应得到“**They wrote a summary in pairs**”的相符回答，并能点击相应来源引用核对原文（若仅给出整份短文来源引用也接受）。这一步成功才有NotebookLM`source_imported`+`question_answered`+`citation_checked`的真实基础。
5. 同时核查被浏览器实际使用的Notebook应用、登录、精确API/来源域名是否都在同一个AI出口；如发现`googleapis`/`gstatic`下的**具体域名**走别的分流，先分类与实际故障关联，必要时只对**已复现问题的精确主机**做路由器本地隔离覆盖实验，不直接扩大整个域名后缀。
6. 上述成功在两个分开时间窗复测稳定性；仅在至少1主1备且NotebookLM真实导入问答成立时，继续受控实现动态地区组选线及故障接替，优先不影响正常家庭网络。

## 唯一下一步

**取得路由器同一人工AI节点下的最小真实浏览器业务回执，NotebookLM优先：工作区+粘贴测试来源+来源问答/引用，以及AI应用/登录/导入的同出口路由归属**。之前的网页/HTTP探针绝不复测为“有效节点”；该回执足够后，再判断是否仅缺某条精确Notebook域名路由，或是账号/平台/出口风控条件，再以最小、可回滚的路由器本地AI-only配置试验修复。当前保持`BUSINESS_VERIFIED=NO`、`AUTO_SWITCH=OFF`、`PRODUCTION_WRITES=NONE`。全订阅和按地区增量的长期P0规格不变。
