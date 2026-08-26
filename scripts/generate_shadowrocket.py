from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE_INI = ROOT / "Clash-Li.ini"
OUTPUT = ROOT / "generated" / "Shadowrocket.conf"


# ==========================================================
# Shadowrocket 固定设置
# ==========================================================

GENERAL = """[General]
bypass-system = true
skip-proxy = 192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,127.0.0.1,localhost,*.local,captive.apple.com
udp-policy-not-supported-behaviour = REJECT
block-quic = all-proxy
"""


# Shadowrocket 平台额外保留的入口
EXTRA_WRAPPER_CHOICES = {
    "⚡ 低延迟": ["所有"],
    "📶 高带宽": ["所有"],
}


# ==========================================================
# 数据结构
# ==========================================================

@dataclass
class Group:
    name: str
    kind: str
    tokens: list[str]


# ==========================================================
# 读取 Clash-Li.ini
# ==========================================================

def parse_ini(
    path: Path,
) -> tuple[list[tuple[str, str]], list[Group]]:
    """
    读取 Clash-Li.ini 中：

    ruleset=
    custom_proxy_group=
    """

    rulesets: list[tuple[str, str]] = []
    groups: list[Group] = []

    text = path.read_text(
        encoding="utf-8-sig",
    )

    for raw in text.splitlines():

        line = raw.strip()

        if not line:
            continue

        if line.startswith(";"):
            continue

        if line.startswith("#"):
            continue

        # --------------------------------------------------
        # ruleset
        # --------------------------------------------------

        if line.startswith("ruleset="):

            body = line[len("ruleset="):]

            if "," not in body:
                raise ValueError(
                    f"无法解析 ruleset：{line}"
                )

            policy, target = body.split(
                ",",
                1,
            )

            rulesets.append(
                (
                    policy.strip(),
                    target.strip(),
                )
            )

            continue

        # --------------------------------------------------
        # custom_proxy_group
        # --------------------------------------------------

        if line.startswith(
            "custom_proxy_group="
        ):

            body = line[
                len("custom_proxy_group="):
            ]

            parts = body.split("`")

            if len(parts) < 2:
                raise ValueError(
                    f"无法解析策略组：{line}"
                )

            name = parts[0].strip()
            kind = parts[1].strip()

            tokens = [
                part.strip()
                for part in parts[2:]
                if part.strip()
            ]

            groups.append(
                Group(
                    name=name,
                    kind=kind,
                    tokens=tokens,
                )
            )

    return rulesets, groups


# ==========================================================
# 基础解析
# ==========================================================

def is_url(token: str) -> bool:

    return token.startswith(
        (
            "http://",
            "https://",
        )
    )


def is_params(token: str) -> bool:
    """
    支持：

    180,5
    180,5,100
    """

    return bool(
        re.fullmatch(
            r"\d+(?:,\d+){1,3}",
            token,
        )
    )


def parse_params(
    token: str | None,
) -> tuple[int, int, int]:
    """
    subconverter：

    interval,timeout,tolerance

    例如：

    180,5,100

    fallback 可能是：

    180,5
    """

    interval = 600
    timeout = 5
    tolerance = 100

    if not token:

        return (
            interval,
            timeout,
            tolerance,
        )

    parts = token.split(",")

    if (
        len(parts) >= 1
        and parts[0].isdigit()
    ):
        interval = int(
            parts[0]
        )

    if (
        len(parts) >= 2
        and parts[1].isdigit()
    ):
        timeout = int(
            parts[1]
        )

    if (
        len(parts) >= 3
        and parts[2].isdigit()
    ):
        tolerance = int(
            parts[2]
        )

    return (
        interval,
        timeout,
        tolerance,
    )


# ==========================================================
# 策略组 token 解析
# ==========================================================

def group_refs(
    tokens: list[str],
) -> list[str]:
    """
    取得：

    []🇹🇼台湾
    []DIRECT
    []REJECT

    并去掉 []
    """

    refs: list[str] = []

    for token in tokens:

        if token.startswith("[]"):

            refs.append(
                token[2:]
            )

    return refs


def group_regex(
    tokens: list[str],
) -> str | None:
    """
    找到 custom_proxy_group 中的节点正则。

    排除：

    []策略组
    URL
    180,5,100
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


def group_url(
    tokens: list[str],
) -> str:

    for token in tokens:

        if is_url(token):

            return token

    return (
        "https://www.gstatic.com/"
        "generate_204"
    )


def group_params(
    tokens: list[str],
) -> tuple[int, int, int]:

    for token in reversed(
        tokens
    ):

        if is_params(token):

            return parse_params(
                token
            )

    return parse_params(
        None
    )


# ==========================================================
# RuleSet URL 转换
# ==========================================================

def shadowrocket_ruleset_url(
    url: str,
) -> str:
    """
    Blackmatrix7 Clash 规则：

    /rule/Clash/

    自动转换：

    /rule/Shadowrocket/

    你的 AI.list / liandu2024 保持不变。
    """

    marker = (
        "raw.githubusercontent.com/"
        "blackmatrix7/"
        "ios_rule_script/"
    )

    if marker not in url:

        return url

    # ------------------------------------------------------
    # Global 特殊处理
    # ------------------------------------------------------

    if (
        "/rule/Clash/"
        "Global/"
        "Global.list"
        in url
    ):

        return (
            "https://raw.githubusercontent.com/"
            "blackmatrix7/"
            "ios_rule_script/"
            "release/rule/"
            "Shadowrocket/"
            "Proxy/"
            "Proxy.list"
        )

    # ------------------------------------------------------
    # 其他 Blackmatrix Clash 规则
    # ------------------------------------------------------

    if "/rule/Clash/" in url:

        return url.replace(
            "/rule/Clash/",
            "/rule/Shadowrocket/",
        )

    return url


# ==========================================================
# 手动组名称
# ==========================================================

def get_manual_name(
    auto_name: str,
) -> str:
    """
    🇹🇼台湾-自动
        ↓
    🇹🇼台湾-手动
    """

    base = auto_name.removesuffix(
        "-自动"
    )

    return (
        f"{base}-手动"
    )


# ==========================================================
# select 组生成
# ==========================================================

def build_select_line(
    group: Group,
    auto_groups: dict[str, Group],
) -> str:

    refs = group_refs(
        group.tokens
    )

    original_first = (
        refs[0]
        if refs
        else None
    )

    auto_name = (
        f"{group.name}-自动"
    )

    manual_name = (
        f"{group.name}-手动"
    )

    # ======================================================
    # 如果存在对应 xxx-自动
    #
    # Shadowrocket 自动补：
    #
    # xxx-自动
    # xxx-手动
    # ======================================================

    if auto_name in auto_groups:

        # --------------------------------------------------
        # 自动组
        # --------------------------------------------------

        if auto_name not in refs:

            refs.append(
                auto_name
            )

        # --------------------------------------------------
        # 手动组
        # --------------------------------------------------

        if manual_name not in refs:

            if auto_name in refs:

                index = refs.index(
                    auto_name
                )

                refs.insert(
                    index + 1,
                    manual_name,
                )

            else:

                refs.append(
                    manual_name
                )

        # --------------------------------------------------
        # Shadowrocket 专属额外入口
        # --------------------------------------------------

        extras = (
            EXTRA_WRAPPER_CHOICES.get(
                group.name,
                [],
            )
        )

        for extra in extras:

            if extra not in refs:

                refs.append(
                    extra
                )

        # --------------------------------------------------
        # 防空组
        # --------------------------------------------------

        if "REJECT" not in refs:

            refs.append(
                "REJECT"
            )

    regex = group_regex(
        group.tokens
    )

    # ======================================================
    # 纯正则 select
    # ======================================================

    if regex and not refs:

        return (
            f"{group.name} = select,"
            f"policy-regex-filter={regex}"
        )

    # ======================================================
    # 完全没有内容
    # ======================================================

    if not refs:

        refs = [
            "DIRECT",
            "REJECT",
        ]

    # ======================================================
    # 默认选择
    # ======================================================

    default = (
        original_first
        or refs[0]
    )

    return (
        f"{group.name} = select,"
        + ",".join(refs)
        + f",policy-select-name={default}"
    )


# ==========================================================
# Shadowrocket 主生成器
# ==========================================================

def generate_shadowrocket(
    rulesets: list[tuple[str, str]],
    groups: list[Group],
) -> str:

    # ------------------------------------------------------
    # 出现在 ruleset 左侧的策略
    # 视为业务策略组
    # ------------------------------------------------------

    policy_names = {
        policy
        for policy, _ in rulesets
    }

    # ------------------------------------------------------
    # INI 本身已有的组
    # ------------------------------------------------------

    source_group_names = {
        group.name
        for group in groups
    }

    # ======================================================
    # 找到全部 xxx-自动
    #
    # 关键修改：
    #
    # 原来只有 url-test
    #
    # 现在：
    #
    # url-test
    # fallback
    #
    # 都属于自动组
    # ======================================================

    auto_groups: dict[str, Group] = {}

    for group in groups:

        if (
            group.kind
            in (
                "url-test",
                "fallback",
            )
            and group.name.endswith(
                "-自动"
            )
        ):

            auto_groups[
                group.name
            ] = group

    # ======================================================
    # 节点池 / 国家 / 运营商
    # ======================================================

    infrastructure = [
        group
        for group in groups
        if group.name
        not in policy_names
    ]

    # ======================================================
    # AI / GitHub / 流媒体等业务组
    # ======================================================

    business = [
        group
        for group in groups
        if group.name
        in policy_names
    ]

    lines: list[str] = [
        GENERAL.rstrip(),
        "",
        "[Proxy Group]",
        (
            "# ===== 从 Clash-Li.ini "
            "自动生成 ====="
        ),
    ]

    # 防止自动生成重复手动组
    emitted_manual: set[str] = set()

    # ======================================================
    # 自动生成 xxx-手动
    # ======================================================

    def emit_manual_group(
        group: Group,
        regex: str | None,
    ) -> None:

        if not group.name.endswith(
            "-自动"
        ):
            return

        if not regex:
            return

        manual_name = (
            get_manual_name(
                group.name
            )
        )

        # INI 已经自己定义
        if (
            manual_name
            in source_group_names
        ):
            return

        # 本轮已经输出
        if (
            manual_name
            in emitted_manual
        ):
            return

        lines.append(
            f"{manual_name} = select,"
            f"policy-regex-filter={regex}"
        )

        emitted_manual.add(
            manual_name
        )

    # ======================================================
    # 输出单个策略组
    # ======================================================

    def emit_group(
        group: Group,
    ) -> None:

        # ==================================================
        # URL-TEST
        # ==================================================

        if group.kind == "url-test":

            refs = group_refs(
                group.tokens
            )

            regex = group_regex(
                group.tokens
            )

            url = group_url(
                group.tokens
            )

            (
                interval,
                timeout,
                tolerance,
            ) = group_params(
                group.tokens
            )

            pieces: list[str] = [
                f"{group.name} = url-test"
            ]

            # ------------------------------------------------
            # 如果有 []策略组引用
            # ------------------------------------------------

            if refs:

                pieces.extend(
                    refs
                )

            # ------------------------------------------------
            # 节点正则
            # ------------------------------------------------

            if regex:

                pieces.append(
                    "policy-regex-filter="
                    f"{regex}"
                )

            pieces.extend(
                [
                    (
                        "interval="
                        f"{interval}"
                    ),
                    (
                        "timeout="
                        f"{timeout}"
                    ),
                    (
                        "tolerance="
                        f"{tolerance}"
                    ),
                    (
                        "url="
                        f"{url}"
                    ),
                ]
            )

            lines.append(
                ",".join(
                    pieces
                )
            )

            # 自动生成 xxx-手动
            emit_manual_group(
                group,
                regex,
            )

            return

        # ==================================================
        # FALLBACK
        # ==================================================
        #
        # 关键修改：
        #
        # 原来：
        #
        # fallback 只处理 []引用
        #
        # 如果只有 regex：
        #
        # refs = []
        # ↓
        # DIRECT
        #
        #
        # 现在：
        #
        # fallback 同时支持：
        #
        # 1. []策略组引用
        # 2. policy-regex-filter
        #
        # ==================================================

        if group.kind == "fallback":

            refs = group_refs(
                group.tokens
            )

            regex = group_regex(
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

            pieces: list[str] = [
                f"{group.name} = fallback"
            ]

            # ------------------------------------------------
            # []引用
            # ------------------------------------------------

            if refs:

                pieces.extend(
                    refs
                )

            # ------------------------------------------------
            # 正则节点池
            # ------------------------------------------------

            if regex:

                pieces.append(
                    "policy-regex-filter="
                    f"{regex}"
                )

            # ------------------------------------------------
            # 真正空组才使用 DIRECT
            # ------------------------------------------------

            if (
                not refs
                and not regex
            ):

                pieces.append(
                    "DIRECT"
                )

            # ------------------------------------------------
            # fallback 参数
            # ------------------------------------------------

            pieces.extend(
                [
                    (
                        "url="
                        f"{url}"
                    ),
                    (
                        "interval="
                        f"{interval}"
                    ),
                    (
                        "timeout="
                        f"{timeout}"
                    ),
                ]
            )

            lines.append(
                ",".join(
                    pieces
                )
            )

            # ------------------------------------------------
            # fallback 同样生成手动池
            # ------------------------------------------------

            emit_manual_group(
                group,
                regex,
            )

            return

        # ==================================================
        # SELECT
        # ==================================================

        if group.kind == "select":

            line = build_select_line(
                group,
                auto_groups,
            )

            lines.append(
                line
            )

            return

        # ==================================================
        # 不支持类型
        # ==================================================

        raise ValueError(
            "暂不支持的策略组类型："
            f"{group.kind} "
            f"({group.name})"
        )

    # ======================================================
    # 先输出节点池 / 国家 / 运营商
    # ======================================================

    lines.append(
        (
            "# ===== 节点池 / 地区 / "
            "运营商 ====="
        )
    )

    for group in infrastructure:

        emit_group(
            group
        )

    # ======================================================
    # 再输出业务策略组
    # ======================================================

    lines.extend(
        [
            "",
            "# ===== 业务分流组 =====",
        ]
    )

    for group in business:

        emit_group(
            group
        )

    # ======================================================
    # Rule
    # ======================================================

    lines.extend(
        [
            "",
            "[Rule]",
            (
                "# ===== 从 Clash-Li.ini "
                "ruleset 自动生成 ====="
            ),
        ]
    )

    final_policy = "DIRECT"

    for (
        policy,
        target,
    ) in rulesets:

        # --------------------------------------------------
        # FINAL
        # --------------------------------------------------

        if target == "[]FINAL":

            final_policy = policy

            continue

        # --------------------------------------------------
        # 其他 [] 内联规则暂不猜测
        # --------------------------------------------------

        if target.startswith("[]"):

            raise ValueError(
                "发现尚未支持的内联 ruleset："
                f"ruleset="
                f"{policy},"
                f"{target}"
            )

        # --------------------------------------------------
        # 转换规则 URL
        # --------------------------------------------------

        url = (
            shadowrocket_ruleset_url(
                target
            )
        )

        lines.append(
            f"RULE-SET,"
            f"{url},"
            f"{policy}"
        )

    # ======================================================
    # Shadowrocket 平台直连规则
    # ======================================================

    lines.extend(
        [
            "",
            (
                "# ===== Shadowrocket "
                "平台专属直连规则 ====="
            ),
            (
                "RULE-SET,"
                "https://raw.githubusercontent.com/"
                "blackmatrix7/"
                "ios_rule_script/"
                "master/rule/"
                "Shadowrocket/"
                "Lan/"
                "Lan.list,"
                "DIRECT"
            ),
            "GEOIP,CN,DIRECT",
            "",
            f"FINAL,{final_policy}",
            "",
        ]
    )

    return "\n".join(
        lines
    )


# ==========================================================
# MAIN
# ==========================================================

def main() -> None:

    if not SOURCE_INI.exists():

        raise FileNotFoundError(
            "找不到主配置："
            f"{SOURCE_INI}"
        )

    rulesets, groups = (
        parse_ini(
            SOURCE_INI
        )
    )

    OUTPUT.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    content = (
        generate_shadowrocket(
            rulesets,
            groups,
        )
    )

    OUTPUT.write_text(
        content,
        encoding="utf-8",
    )

    print(
        "Generated:",
        OUTPUT.relative_to(
            ROOT
        ),
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
