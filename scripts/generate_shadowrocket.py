from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE_INI = ROOT / "Clash-Li.ini"
OUTPUT = ROOT / "generated" / "Shadowrocket.conf"


# Shadowrocket 专属固定设置。
# 这部分不从 Clash-Li.ini 生成，因为属于 iOS / Shadowrocket 平台设置。
GENERAL = """[General]
bypass-system = true
skip-proxy = 192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,127.0.0.1,localhost,*.local,captive.apple.com
udp-policy-not-supported-behaviour = REJECT
block-quic = all-proxy
"""


# Shadowrocket 平台上的额外手动入口。
# 不改变 Clash-Li.ini，只是在 iOS 上保留你现在习惯的选择方式。
EXTRA_WRAPPER_CHOICES = {
    "⚡ 低延迟": ["所有"],
    "📶 高带宽": ["所有"],
}


@dataclass
class Group:
    name: str
    kind: str
    tokens: list[str]


def parse_ini(path: Path) -> tuple[list[tuple[str, str]], list[Group]]:
    """读取 Clash-Li.ini 中的 ruleset 和 custom_proxy_group。"""

    rulesets: list[tuple[str, str]] = []
    groups: list[Group] = []

    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()

        if not line:
            continue

        if line.startswith(";") or line.startswith("#"):
            continue

        if line.startswith("ruleset="):
            body = line[len("ruleset="):]

            if "," not in body:
                raise ValueError(f"无法解析 ruleset：{line}")

            policy, target = body.split(",", 1)

            rulesets.append(
                (
                    policy.strip(),
                    target.strip(),
                )
            )

            continue

        if line.startswith("custom_proxy_group="):
            body = line[len("custom_proxy_group="):]
            parts = body.split("`")

            if len(parts) < 2:
                raise ValueError(f"无法解析策略组：{line}")

            groups.append(
                Group(
                    name=parts[0].strip(),
                    kind=parts[1].strip(),
                    tokens=[
                        part.strip()
                        for part in parts[2:]
                        if part.strip()
                    ],
                )
            )

    return rulesets, groups


def is_url(token: str) -> bool:
    return token.startswith("http://") or token.startswith("https://")


def is_params(token: str) -> bool:
    return bool(
        re.fullmatch(
            r"\d+(?:,\d+){1,3}",
            token,
        )
    )


def parse_params(token: str | None) -> tuple[int, int, int]:
    """
    subconverter:
        interval,timeout,tolerance

    例如：
        180,5,100
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


def group_refs(tokens: list[str]) -> list[str]:
    """取得 []策略组 / []DIRECT / []REJECT。"""

    return [
        token[2:]
        for token in tokens
        if token.startswith("[]")
    ]


def group_regex(tokens: list[str]) -> str | None:
    """取得节点筛选正则。"""

    for token in tokens:

        if token.startswith("[]"):
            continue

        if is_url(token):
            continue

        if is_params(token):
            continue

        return token

    return None


def group_url(tokens: list[str]) -> str:
    for token in tokens:

        if is_url(token):
            return token

    return "https://www.gstatic.com/generate_204"


def group_params(tokens: list[str]) -> tuple[int, int, int]:
    for token in reversed(tokens):

        if is_params(token):
            return parse_params(token)

    return parse_params(None)


def shadowrocket_ruleset_url(url: str) -> str:
    """
    Blackmatrix7 的 Clash 规则自动转换为 Shadowrocket 规则。

    例如：
    /rule/Clash/AppleTV/AppleTV.list

    自动变成：
    /rule/Shadowrocket/AppleTV/AppleTV.list
    """

    if "raw.githubusercontent.com/blackmatrix7/ios_rule_script/" in url:

        # Clash Global 在你目前 Shadowrocket 配置中
        # 对应使用 Shadowrocket Proxy.list。
        if "/rule/Clash/Global/Global.list" in url:

            return (
                "https://raw.githubusercontent.com/"
                "blackmatrix7/ios_rule_script/"
                "release/rule/Shadowrocket/Proxy/Proxy.list"
            )

        if "/rule/Clash/" in url:

            return url.replace(
                "/rule/Clash/",
                "/rule/Shadowrocket/",
            )

    # 例如：
    # 你的 AI.list
    # liandu2024 的 list
    # 都保持原 URL。
    return url


def build_select_line(
    group: Group,
    auto_groups: dict[str, Group],
) -> str:

    refs = group_refs(group.tokens)

    original_first = refs[0] if refs else None

    auto_name = f"{group.name}-自动"
    manual_name = f"{group.name}-手动"

    # ------------------------------------------------
    # Shadowrocket 特有逻辑：
    #
    # Clash：
    # 🇭🇰香港-自动
    # 🇭🇰香港
    #
    # Shadowrocket 自动生成：
    # 🇭🇰香港-自动
    # 🇭🇰香港-手动
    # 🇭🇰香港
    #
    # 手动池直接使用同一条 regex。
    # ------------------------------------------------

    if auto_name in auto_groups:

        if auto_name not in refs:
            refs.append(auto_name)

        if manual_name not in refs:

            if auto_name in refs:

                index = refs.index(auto_name)

                refs.insert(
                    index + 1,
                    manual_name,
                )

            else:

                refs.append(manual_name)

        # 保留你现有 Shadowrocket 中
        # 低延迟 / 高带宽的“所有”入口。
        for extra in EXTRA_WRAPPER_CHOICES.get(
            group.name,
            [],
        ):

            if extra not in refs:
                refs.append(extra)

        # 节点池没有可用节点时，
        # Shadowrocket 仍然保留 REJECT。
        if "REJECT" not in refs:
            refs.append("REJECT")

    regex = group_regex(group.tokens)

    # 极少数只有 regex、没有引用组的 select。
    if regex and not refs:

        return (
            f"{group.name} = select,"
            f"policy-regex-filter={regex}"
        )

    if not refs:

        refs = [
            "DIRECT",
            "REJECT",
        ]

    default = original_first or refs[0]

    return (
        f"{group.name} = select,"
        + ",".join(refs)
        + f",policy-select-name={default}"
    )


def generate_shadowrocket(
    rulesets: list[tuple[str, str]],
    groups: list[Group],
) -> str:

    # 出现在 ruleset 左侧的策略，
    # 视为业务分流组。
    policy_names = {
        policy
        for policy, _ in rulesets
    }

    source_group_names = {
        group.name
        for group in groups
    }

    # 找出全部 xxx-自动。
    auto_groups: dict[str, Group] = {}

    for group in groups:

        if (
            group.kind == "url-test"
            and group.name.endswith("-自动")
        ):

            auto_groups[group.name] = group

    # Shadowrocket 中先生成：
    # 节点池 / 国家 / 运营商
    #
    # 最后生成：
    # AI / AppleTV / Disney / Steam 等业务组。
    infrastructure = [
        group
        for group in groups
        if group.name not in policy_names
    ]

    business = [
        group
        for group in groups
        if group.name in policy_names
    ]

    lines: list[str] = [
        GENERAL.rstrip(),
        "",
        "[Proxy Group]",
        "# ===== 从 Clash-Li.ini 自动生成 =====",
    ]

    emitted_manual: set[str] = set()

    def emit_group(group: Group) -> None:

        # ==================================================
        # url-test
        # ==================================================

        if group.kind == "url-test":

            regex = group_regex(group.tokens)

            url = group_url(group.tokens)

            (
                interval,
                timeout,
                tolerance,
            ) = group_params(group.tokens)

            pieces = [
                f"{group.name} = url-test"
            ]

            if regex:

                pieces.append(
                    f"policy-regex-filter={regex}"
                )

            pieces.extend(
                [
                    f"interval={interval}",
                    f"timeout={timeout}",
                    f"tolerance={tolerance}",
                    f"url={url}",
                ]
            )

            lines.append(
                ",".join(pieces)
            )

            # 自动生成 Shadowrocket 手动池。
            if (
                group.name.endswith("-自动")
                and regex
            ):

                base = group.name.removesuffix(
                    "-自动"
                )

                manual_name = (
                    f"{base}-手动"
                )

                # 如果未来你自己在 INI 里已经定义手动组，
                # 就不会重复生成。
                if (
                    manual_name
                    not in source_group_names
                    and manual_name
                    not in emitted_manual
                ):

                    lines.append(
                        f"{manual_name} = select,"
                        f"policy-regex-filter={regex}"
                    )

                    emitted_manual.add(
                        manual_name
                    )

            return

        # ==================================================
        # fallback
        # ==================================================

        if group.kind == "fallback":

            refs = group_refs(
                group.tokens
            )

            url = group_url(
                group.tokens
            )

            (
                interval,
                timeout,
                _,
            ) = group_params(
                group.tokens
            )

            if not refs:
                refs = ["DIRECT"]

            lines.append(
                f"{group.name} = fallback,"
                + ",".join(refs)
                + f",url={url}"
                + f",interval={interval}"
                + f",timeout={timeout}"
            )

            return

        # ==================================================
        # select
        # ==================================================

        if group.kind == "select":

            lines.append(
                build_select_line(
                    group,
                    auto_groups,
                )
            )

            return

        raise ValueError(
            "暂不支持的策略组类型："
            f"{group.kind} "
            f"({group.name})"
        )

    # ------------------------------------------------
    # 节点池 / 国家 / 运营商
    # ------------------------------------------------

    lines.append(
        "# ===== 节点池 / 地区 / 运营商 ====="
    )

    for group in infrastructure:
        emit_group(group)

    # ------------------------------------------------
    # 业务策略
    # ------------------------------------------------

    lines.extend(
        [
            "",
            "# ===== 业务分流组 =====",
        ]
    )

    for group in business:
        emit_group(group)

    # ------------------------------------------------
    # Rule
    # ------------------------------------------------

    lines.extend(
        [
            "",
            "[Rule]",
            "# ===== 从 Clash-Li.ini ruleset 自动生成 =====",
        ]
    )

    final_policy = "DIRECT"

    for policy, target in rulesets:

        # subconverter 的：
        #
        # ruleset=🏠 国内,[]FINAL
        #
        # Shadowrocket 转换为：
        #
        # FINAL,🏠 国内
        if target == "[]FINAL":

            final_policy = policy

            continue

        # 当前配置若以后出现其他 [] 内联规则，
        # 不进行静默猜测，直接让 Action 报错，
        # 防止自动生成错误配置。
        if target.startswith("[]"):

            raise ValueError(
                "发现尚未支持的内联 ruleset："
                f"ruleset={policy},{target}"
            )

        url = shadowrocket_ruleset_url(
            target
        )

        lines.append(
            f"RULE-SET,{url},{policy}"
        )

    # ------------------------------------------------
    # Shadowrocket 平台专属规则
    # ------------------------------------------------

    lines.extend(
        [
            "",
            "# ===== Shadowrocket 平台专属直连规则 =====",
            (
                "RULE-SET,"
                "https://raw.githubusercontent.com/"
                "blackmatrix7/ios_rule_script/"
                "master/rule/Shadowrocket/Lan/Lan.list,"
                "DIRECT"
            ),
            "GEOIP,CN,DIRECT",
            "",
            f"FINAL,{final_policy}",
            "",
        ]
    )

    return "\n".join(lines)


def main() -> None:

    if not SOURCE_INI.exists():

        raise FileNotFoundError(
            f"找不到主配置：{SOURCE_INI}"
        )

    rulesets, groups = parse_ini(
        SOURCE_INI
    )

    OUTPUT.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    content = generate_shadowrocket(
        rulesets,
        groups,
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


if __name__ == "__main__":
    main()
