from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re


# ==========================================================
# 路径
# ==========================================================

ROOT = Path(__file__).resolve().parents[1]
SOURCE_INI = ROOT / "Clash-Li.ini"
OUTPUT = ROOT / "generated" / "Shadowrocket.conf"


# ==========================================================
# Shadowrocket 固定基础设置
#
# 这里只保留客户端运行所需的基础设置；
# 不在这里增加任何业务分流、策略组、DIRECT/REJECT、
# LAN/GEOIP 等 INI 中未定义的策略内容。
# ==========================================================

GENERAL = """[General]
bypass-system = true
skip-proxy = 192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,127.0.0.1,localhost,*.local,captive.apple.com
udp-policy-not-supported-behaviour = REJECT
block-quic = all-proxy
"""


# ==========================================================
# 数据结构
# ==========================================================

@dataclass(frozen=True)
class Group:
    name: str
    kind: str
    tokens: list[str]


# ==========================================================
# 读取 Clash-Li.ini
# ==========================================================

def parse_ini(path: Path) -> tuple[list[tuple[str, str]], list[Group]]:
    """
    仅读取 Clash-Li.ini 中与 Shadowrocket 生成有关的两类内容：

    1. ruleset=
    2. custom_proxy_group=

    其他参数保持由原有 Subconverter / Clash 体系处理。
    """

    rulesets: list[tuple[str, str]] = []
    groups: list[Group] = []

    text = path.read_text(encoding="utf-8-sig")

    for raw in text.splitlines():
        line = raw.strip()

        if not line or line.startswith((";", "#")):
            continue

        if line.startswith("ruleset="):
            body = line[len("ruleset="):]

            if "," not in body:
                # 非法行直接忽略，不额外创造替代规则
                continue

            policy, target = body.split(",", 1)
            policy = policy.strip()
            target = target.strip()

            if policy and target:
                rulesets.append((policy, target))

            continue

        if line.startswith("custom_proxy_group="):
            body = line[len("custom_proxy_group="):]
            parts = body.split("`")

            if len(parts) < 2:
                continue

            name = parts[0].strip()
            kind = parts[1].strip()
            tokens = [
                part.strip()
                for part in parts[2:]
                if part.strip()
            ]

            if name and kind:
                groups.append(
                    Group(
                        name=name,
                        kind=kind,
                        tokens=tokens,
                    )
                )

    return rulesets, groups


# ==========================================================
# Token 基础判断
# ==========================================================

def is_url(token: str) -> bool:
    return token.startswith(("http://", "https://"))


def is_params(token: str) -> bool:
    """
    支持当前 INI 中常见形式：

    180,5
    180,5,100

    同时兼容最多四段纯数字参数，
    防止未来参数被误识别为节点正则。
    """
    return bool(
        re.fullmatch(
            r"\d+(?:,\d+){1,3}",
            token,
        )
    )


def parse_params(token: str | None) -> tuple[int, int, int]:
    """
    返回：
        interval
        timeout
        tolerance

    url-test 常见：
        180,5,100

    fallback 常见：
        180,5
    """

    interval = 600
    timeout = 5
    tolerance = 100

    if not token:
        return interval, timeout, tolerance

    parts = token.split(",")

    if len(parts) >= 1 and parts[0].isdigit():
        interval = int(parts[0])

    if len(parts) >= 2 and parts[1].isdigit():
        timeout = int(parts[1])

    if len(parts) >= 3 and parts[2].isdigit():
        tolerance = int(parts[2])

    return interval, timeout, tolerance


# ==========================================================
# custom_proxy_group token 解析
# ==========================================================

def group_refs(tokens: list[str]) -> list[str]:
    """
    INI：
        []🇹🇼台湾
        []DIRECT
        []REJECT

    Shadowrocket：
        🇹🇼台湾
        DIRECT
        REJECT

    只做语法转换，不新增任何引用。
    """
    return [
        token[2:]
        for token in tokens
        if token.startswith("[]")
    ]


def group_regex(tokens: list[str]) -> str | None:
    """
    找到策略组中的节点筛选正则。

    排除：
        []策略组引用
        URL
        数字参数
    """

    for token in tokens:
        if token.startswith("[]"):
            continue

        if is_url(token):
            continue

        if is_params(token):
            continue

        return token

    return None


def group_url(tokens: list[str]) -> str | None:
    """
    返回 INI 中明确写出的测速 URL。

    不在这里人为增加新的业务策略。
    对 url-test / fallback，如果 INI 没写 URL，
    生成时才使用 Shadowrocket 常规测速地址作为纯客户端语法默认值。
    """

    for token in tokens:
        if is_url(token):
            return token

    return None


def group_params(tokens: list[str]) -> tuple[int, int, int]:
    for token in reversed(tokens):
        if is_params(token):
            return parse_params(token)

    return parse_params(None)


# ==========================================================
# RuleSet URL 平台适配
# ==========================================================

def shadowrocket_ruleset_url(url: str) -> str:
    """
    只做“同一规则集在不同客户端中的路径适配”。

    Blackmatrix7：
        /rule/Clash/
    转为：
        /rule/Shadowrocket/

    用户自己的 AI.list、liandu2024 等地址保持不变。

    Global 在 Blackmatrix7 的 Shadowrocket 发布结构中使用 Proxy.list，
    因此只做对应客户端路径转换，不改变它在 INI 中的策略归属。
    """

    marker = (
        "raw.githubusercontent.com/"
        "blackmatrix7/"
        "ios_rule_script/"
    )

    if marker not in url:
        return url

    if "/rule/Clash/Global/Global.list" in url:
        return (
            "https://raw.githubusercontent.com/"
            "blackmatrix7/"
            "ios_rule_script/"
            "release/rule/"
            "Shadowrocket/"
            "Proxy/"
            "Proxy.list"
        )

    if "/rule/Clash/" in url:
        return url.replace(
            "/rule/Clash/",
            "/rule/Shadowrocket/",
        )

    return url


# ==========================================================
# 策略组生成
# ==========================================================

def build_select_line(group: Group) -> str:
    """
    select 严格按照 INI 输出：

    - INI 中有 []引用 -> 输出对应引用
    - INI 中有正则 -> 输出 policy-regex-filter
    - INI 中没有 DIRECT -> 不补 DIRECT
    - INI 中没有 REJECT -> 不补 REJECT
    - 不生成 policy-select-name
    - 不生成额外“手动组”
    """

    refs = group_refs(group.tokens)
    regex = group_regex(group.tokens)

    pieces = [f"{group.name} = select"]

    if refs:
        pieces.extend(refs)

    if regex:
        pieces.append(
            f"policy-regex-filter={regex}"
        )

    return ",".join(pieces)


def build_url_test_line(group: Group) -> str:
    """
    url-test 严格复用 INI 中：
        []引用
        正则
        URL
        interval / timeout / tolerance

    不增加额外节点或策略组。
    """

    refs = group_refs(group.tokens)
    regex = group_regex(group.tokens)
    url = group_url(group.tokens)
    interval, timeout, tolerance = group_params(group.tokens)

    pieces = [f"{group.name} = url-test"]

    if refs:
        pieces.extend(refs)

    if regex:
        pieces.append(
            f"policy-regex-filter={regex}"
        )

    # URL / 参数属于客户端运行语法，不属于额外业务策略。
    if url is None:
        url = "https://www.gstatic.com/generate_204"

    pieces.extend(
        [
            f"url={url}",
            f"interval={interval}",
            f"timeout={timeout}",
            f"tolerance={tolerance}",
        ]
    )

    return ",".join(pieces)


def build_fallback_line(group: Group) -> str:
    """
    fallback 同时支持：

    1. fallback + []组引用
       例如：
       ⚡低延迟-兜底
       📶高带宽-兜底

    2. fallback + 正则节点池
       例如：
       🇹🇼台湾-自动

    不再出现旧逻辑：
        没有 refs -> 自动补 DIRECT

    INI 没有 DIRECT，就绝不生成 DIRECT。
    """

    refs = group_refs(group.tokens)
    regex = group_regex(group.tokens)
    url = group_url(group.tokens)
    interval, timeout, _ = group_params(group.tokens)

    pieces = [f"{group.name} = fallback"]

    if refs:
        pieces.extend(refs)

    if regex:
        pieces.append(
            f"policy-regex-filter={regex}"
        )

    if url is None:
        url = "https://www.gstatic.com/generate_204"

    pieces.extend(
        [
            f"url={url}",
            f"interval={interval}",
            f"timeout={timeout}",
        ]
    )

    return ",".join(pieces)


def build_group_line(group: Group) -> str | None:
    """
    当前 INI 实际使用：
        select
        url-test
        fallback

    只针对这些已使用类型做 Shadowrocket 适配。
    """

    if group.kind == "select":
        return build_select_line(group)

    if group.kind == "url-test":
        return build_url_test_line(group)

    if group.kind == "fallback":
        return build_fallback_line(group)

    # 不猜测未知策略类型，也不新增替代策略。
    return None


# ==========================================================
# Shadowrocket 配置生成
# ==========================================================

def generate_shadowrocket(
    rulesets: list[tuple[str, str]],
    groups: list[Group],
) -> str:

    lines: list[str] = [
        GENERAL.rstrip(),
        "",
        "[Proxy Group]",
        "# ===== 严格由 Clash-Li.ini 自动转换 =====",
    ]

    # ------------------------------------------------------
    # 策略组
    # ------------------------------------------------------

    for group in groups:
        line = build_group_line(group)

        if line:
            lines.append(line)

    # ------------------------------------------------------
    # Rule
    # ------------------------------------------------------

    lines.extend(
        [
            "",
            "[Rule]",
            "# ===== 严格由 Clash-Li.ini ruleset 自动转换 =====",
        ]
    )

    for policy, target in rulesets:

        # INI：
        # ruleset=🏠 国内,[]FINAL
        #
        # Shadowrocket：
        # FINAL,🏠 国内
        if target == "[]FINAL":
            lines.append(
                f"FINAL,{policy}"
            )
            continue

        # 当前 INI 除 FINAL 外均为远程规则集。
        # 如果未来出现其他 [] 内联规则，
        # 这里不擅自推断或新增含义。
        if target.startswith("[]"):
            continue

        url = shadowrocket_ruleset_url(target)

        lines.append(
            f"RULE-SET,{url},{policy}"
        )

    lines.append("")

    content = "\n".join(lines)

    # ------------------------------------------------------
    # 只做“不改变策略含义”的安全检查
    # ------------------------------------------------------

    forbidden_generated_content = (
        "policy-select-name=",
    )

    for item in forbidden_generated_content:
        if item in content:
            raise RuntimeError(
                f"生成结果出现禁止字段：{item}"
            )

    return content


# ==========================================================
# MAIN
# ==========================================================

def main() -> None:

    if not SOURCE_INI.exists():
        raise FileNotFoundError(
            f"找不到主配置：{SOURCE_INI}"
        )

    rulesets, groups = parse_ini(
        SOURCE_INI
    )

    content = generate_shadowrocket(
        rulesets,
        groups,
    )

    OUTPUT.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    OUTPUT.write_text(
        content,
        encoding="utf-8",
    )

    print(
        "Generated:",
        OUTPUT.relative_to(ROOT),
    )

    print(
        "Rulesets:",
        len(rulesets),
    )

    print(
        "Proxy groups:",
        len(groups),
    )

    print(
        "Source of truth: Clash-Li.ini"
    )

    print(
        "Extra business policies: disabled"
    )

    print(
        "policy-select-name: disabled"
    )


if __name__ == "__main__":
    main()
