# NotebookLM 优先：路由器 AI 三平台真实业务首轮验收包（2026-11-14）

**目前状态**：业务未验；此文只定义一次最小可回退的用户浏览器试点。固定候选 Git [fa0bf7d10f9f6f591e9b563335b3be7aff87ffbc](https://github.com/Kimbersy/openclash/commit/fa0bf7d10f9f6f591e9b563335b3be7aff87ffbc)，[全CI #43546898210](https://github.com/Kimbersy/openclash/actions/runs/43546898210) `completed/success`。这**不是**真实登录或设备安装证明。

## 一、交付目标（主线不变）

[P0完整最终验收基线](https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_AI_P0_ACCEPTANCE_CONTRACT.md)：全启用源全节点、三个AI分别验证、所有合格节点进入各自池、双源实际出口国家的动态地区分组、随原订阅真实更新自动增删/失效/继承/重建、稳态主备与故障接替；P0只要求iStoreOS/OpenClash，Clash Mate与Shadowrocket智能扩展为P1。普通/Disney/媒体/GitHub/国内/Worker、现有三端订阅均不得改变。

## 二、这轮已发现并关闭的一个实际资格错误

早先 `scripts/ai_service_stability_dry_run.py` 对NotebookLM的`WORKFLOW_TASKS`只有`workspace_opened/source_imported/question_answered`，但真实浏览器验收文档要求**登录、来源引用与同出口**；业务验收和`qualified_pool`实际入池门槛不同步，存在把旧三步声明错误放进NotebookLM及共享全球/地区组的缺口。

本轮已固定修订：
- **ChatGPT**：`signed_in,prompt_answered,stream_completed,route_consistent`。
- **Gemini**：`signed_in,prompt_answered,route_consistent`。
- **NotebookLM**：`signed_in,workspace_opened,source_imported,question_answered,citation_checked,route_consistent`。
- 真实浏览器结构检查的`CHECKS`与真正入池使用的`WORKFLOW_TASKS`必须**逐项完全一致**，测试明确锁住；缺旧字段/同出口假的节点自动无法进入该平台池，**其他平台的合格资格不应因此被清空**。
- 路由核查识别公共`AI.list`已经包含的**精确Gemini API主机**（如`alkalimakersuite-pa.clients6.google.com`等），避免仅识别`gemini.google.com`导致业务真通却错误阻断。不因此扩展共享`googleapis.com`/`gstatic.com`/`google.com`泛域名规则。
- 回归新增：旧三项Notebook合格声明不能进入Notebook/共享池，ChatGPT池仍保持；任一服务同出口标识为false则共享池拒绝；真实流程与入池校验键永不失配；正常的已列名Gemini API流量不会被误拒，未知共享主机仍待核实。**这些均为合成数据/CI，结果不能自己授予真实`BUSINESS_VERIFIED`资格，也不能解锁安装/切线**。

## 三、唯一需要真人完成的最小业务试点（首先一个当前稳定的人工AI节点）

**设备和安全**：使用**实际经家中iStoreOS路由上网**的电脑浏览器，不使用手机独立Clash/蜂窝代理，否则无法验证路由器P0；仅在现有`🤖 AI`人工select选中的当前正常节点测试，不替换订阅、不启用自动策略、不手动重启网络。一个节点先出回执，不重复扫描58个。测试材料是虚构文本，无任何私有文件。

### NotebookLM（必须先过）

1. 打开个人 NotebookLM（Google当前官方也使用“Gemini Notebook”名称），若已登录无需强行退出再登录，确认能进入个人笔记本列表，并打开一个新建的测试笔记本。
2. 添加**复制粘贴文本**来源，测试文本如下：

   ```text
   North Harbor Library opened a reading workshop on Tuesday.
   Students arrived at nine o'clock. They read a story about a hidden garden.
   After a short break, they wrote a summary in pairs.
   Each pair described the story's main idea and one important detail.
   The teacher collected the summaries before noon.
   ```

3. 在该笔记本问：`What did the students do after the break?`。期待与来源一致的含义：`They wrote a summary in pairs.`。
4. 查看回答给出的来源引用/关联来源是否指向刚添加的测试文本。**短文本可能引用整份来源，而不是逐字定位到某一句，此时允许以整份来源可核对为通过。** 若来源根本未添加、只有网页可达、无对应回答、出现`location=unsupported`，都不算通过。
5. 若可用OpenClash/Mihomo连接页面（非浏览器开发者工具输出原始账号请求），只核对与NotebookLM相关的**主机名**`accounts.google.com`（本次若实际发生登录跳转）、`notebook.google.com`/`notebooklm.google.com`、实际观测到的NotebookLM来源/问答专用主机是否都经过`🤖 AI`并解析到**相同叶节点/出口**。有缓存会话而没有新登录请求不判失败；**不能把同一AI父组名称等同于同一真实出口**。不上传连接URL、Cookie、token、完整IP/账号或原始Notebook内容。

### ChatGPT / Gemini（同一当前手动出口下的顺带验证）

- ChatGPT登录状态有效，发一条无隐私问题，收到完整流式/连续回答；账号403/429需单独记录，并非必定节点断网。
- Gemini当前账户能成功生成一条回答；Google登录（若发生）与主要回答请求应匹配同一AI出口；允许已在公共规则的精确Gemini API主机。

### 对用户最省事的回执内容

只需要告知“**NotebookLM工作区/添加来源/答复/引用**各是否成功；ChatGPT是否完整回复、Gemini是否完整回复；如失败截图**去掉账号/笔记本名/连接IP和敏感URL**的提示”。若恰有OpenClash连接页，则额外提供相关主机`Chains`是否同一AI叶的匿名结论。**没有实际路由器日志时只能记`业务可用待路由归属确认`，不能提升为同出口完全合格。**

## 四、确认当前没有通过的内容

- 用户家中NotebookLM真实浏览器未执行本测试，没有资格`PASS`；01/05/08–11原隔离测试仅入口可达、业务仍UNKNOWN。
- 目前源/运行的完整一致性仍未由正式Mihomo完整连接参数确认，活动订阅后置成功/自动加载与动态地区组正式下发/回滚、Provider未来支持也都未完成；**P0未交付，自动切换继续禁止**。
- 此次没有修改`Clash-Li.ini`、`list/AI.list`、现有Shadowrocket/Android生成器、任何生产设备或订阅；全部变更仅在未合并候选分支。

## 唯一下一步

**取得路由器所用当前人工AI节点的一次NotebookLM真实笔记本测试结果（来源、问答、引用优先）并确认是否同一实际AI出口；同节点顺带ChatGPT/Gemini回答。** 如果失败，只针对真实路由记录里复现的精确主机/出口或具体账号/地区问题提出可回滚的路由器本地修复；若通过，再按一主一备小范围实机验证本次修正后的全量合格池门禁，然后继续原订阅更新联动。
