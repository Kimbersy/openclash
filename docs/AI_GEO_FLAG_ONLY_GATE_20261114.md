# 20份HTTP规则缓存后的唯一Geo配置分叉定位（2026-11-14）

> 这不是重做缓存清点。用户真实已证明20/20 HTTP规则Provider在Mihomo当前HomeDir内有明示缓存文件，0条丢失、越界、未知，20个缓存内容本身尚未读取/验证。**旧`GEO_MODE_ENABLED=1`是三种不同Geo设置的OR位**，不能把它直接解释成Geo自动更新开启。

## 已通过且绝不能重跑

1. 15:46家中实际Mihomo二进制对纯合成单核127.0.0.1:17881 Listener原生`-t`通过、清理成功。
2. 真实私有配置门禁`HOLD_RULE_PROVIDERS`，在任何私有复制和Mihomo`-t`执行前停止、现网未改。
3. 本轮用户规则集清点`RULE_PROVIDER_TOTAL=20 TYPE_HTTP=20 CACHE_LOCAL_REGULAR=20`，`CACHE_MISSING=0 CACHE_OUTSIDE_HOME=0 CACHE_UNSAFE_PATH=0`，`RULESET_REFERENCE_PRESENT=1 GEO_REFERENCE_PRESENT=0 GEO_MODE_ENABLED=1 PROXY_PROVIDERS_PRESENT=0`。`PRIVATE_COPY_TEST=NOT_RUN`。
4. [固定Git `545c78c`](https://github.com/Kimbersy/openclash/commit/545c78cd0518526478adcc5035faa71db024c0a6)、[GitHub CI #43576991210](https://github.com/Kimbersy/openclash/actions/runs/43576991210) `success`：20个**合成**缓存转化为仅测试用途的`type:file` Provider，在保留原RULE-SET引用、AI/非AI规则后，官方Mihomo原生`-t`PASS；**真实HTTP Provider的定时更新/业务、Geo文件以及真实缓存内容不在此验收内**。

## 本轮补上的唯一新事实缺口

官方[Mihomo General](https://wiki.metacubex.one/en/config/general/)说明`geodata-mode`决定dat/mmdb模式，`geo-auto-update`决定是否自动更新，`geox-url`是自定义下载地址，这三项意义不同。

- 新增独立[脚本`scripts/ai_geo_flags_only_readonly.rb`](https://github.com/Kimbersy/openclash/blob/84e1e40cfcbfc6b1ffc5f771f44969a04e34c32d/scripts/ai_geo_flags_only_readonly.rb)，**只读当前实际OpenClash核心配置**，匿名返回：
  - `GEO_DAT_MODE=TRUE/FALSE/UNRECOGNIZED`
  - `GEO_AUTO_UPDATE=TRUE/FALSE/UNRECOGNIZED`
  - `GEO_CUSTOM_URL=PRESENT/ABSENT`
- 仅依赖Ruby`psych`，为设备15:02后已经真实证明可加载；无`timeout`、`open3`、`tempfile`或Python。脚本不读取/复制规则缓存，不输出任何规则名称、私密URL、密码、节点标签、实际路径，不会发起网络、启动Mihomo、打开监听器或切线。
- 合成回归涵盖三种互不等价的Geo模式来源、非法字段类型、无额外Ruby依赖和零业务副作用；[固定Git `84e1e40cfcbfc6b1ffc5f771f44969a04e34c32d`](https://github.com/Kimbersy/openclash/commit/84e1e40cfcbfc6b1ffc5f771f44969a04e34c32d)、[完整GitHub Actions #43577356722](https://github.com/Kimbersy/openclash/actions/runs/43577356722) `completed/success`，包括此前20缓存/官方Mihomo原生`-t`、三端及非AI冻结回归。**仍未在用户家中运行新的Geo专用脚本**。

## 唯一下一步（一条命令，一次匿名回执）

在iStoreOS TTYD执行这条**固定Git SHA**的命令。此操作仅在`/tmp`创建并删除下载的脚本文件，工作脚本只读，不重跑20规则或别的旧验收：

```sh
( umask 077; f="$(mktemp /tmp/ai_geo_XXXXXX)" || exit 1; if curl -fLsS --connect-timeout 8 --max-time 25 -o "$f" "https://raw.githubusercontent.com/Kimbersy/openclash/84e1e40cfcbfc6b1ffc5f771f44969a04e34c32d/scripts/ai_geo_flags_only_readonly.rb"; then ruby "$f" || echo "GEO_RESULT=HOLD_SCRIPT_RUNTIME"; else echo "GEO_RESULT=HOLD_DOWNLOAD_UNAVAILABLE"; fi; rm -f "$f" )
```

只发回`GEO_RESULT`和上述三个`GEO_*`字段。若Geo自动更新为True或提供了下载地址，并不因此自动发起网络，后续仍需要独立验证Geo资产处理逻辑；不能为了通过测试删改生产Geo配置。

下一阶段：按这份精确Geo配置决定能否进一步构建实际20份缓存受保护复制与逐字节对照（单文件与总大小预算），进而在**保证不会向外请求的测试环境**解析仅测试用途的`type:file`映射；真实Provider正式仍是`type:http`。**任何真实配置副本`-t`、生产安装Listener及Controller PUT都必须在安全门禁之后另行审查/授权。**

P0不缩水：全部实际启用机场节点的ChatGPT/Gemini/NotebookLM真实业务资格、独立分组和共享交集池、按双源出口国家动态分组、原订阅成功更新后的增量维护和稳态主备。手机智能化P1；原有Worker、转换、非AI规则不动，`AUTO_SWITCH=OFF LISTENER_INSTALLED=NO BUSINESS=UNKNOWN`。
