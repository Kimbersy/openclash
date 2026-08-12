from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE_INI = ROOT / "Clash-Li.ini"

OUTPUT = (
    ROOT
    / "generated"
    / "Clash-Meta-Android.template.yaml"
)

# 最终由 Cloudflare Worker 注入朋友自己的机场订阅
AIRPORT_URL_PLACEHOLDER = "__AIRPORT_URL__"

PROVIDER_NAME = "Airport"

BUILTIN_PROXIES = {
    "DIRECT",
    "REJECT",
    "REJECT-DROP",
    "PASS",
    "COMPATIBLE",
}


@dataclass
class Group:
    name: str
    kind: str
    tokens: list[str]


# ============================================================
# 读取 Clash-Li.ini
# ============================================================

def parse_ini(
    path: Path,
) -> tuple[
    list[tuple[str, str]],
    list[Group],
]:
    rulesets: list[tuple[str, str]] = []
    groups: list[Group] = []

    text = path.read_text(
        encoding="utf-8-sig"
    )

    for raw in text.splitlines():
        line = raw.strip()

        if not line:
            continue

        if (
            line.startswith(";")
            or line.startswith("#")
        ):
            continue

        # ----------------------------------------------------
        # ruleset=
        # ----------------------------------------------------

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

        # ----------------------------------------------------
        # custom_proxy_group=
        # ----------------------------------------------------

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

            groups.append(
                Group(
                    name=parts[0].strip(),
                    kind=parts[1].strip(),
                    tokens=[
                        token.strip()
                        for token
                        in parts[2:]
                        if token.strip()
                    ],
                )
            )

    return rulesets, groups


# ============================================================
# 基础 token 识别
# ============================================================

def is_url(token: str) -> bool:
    return (
        token.startswith("http://")
        or token.startswith("https://")
    )


def is_params(token: str) -> bool:
    """
    subconverter 当前参数：

    180,5,100

    interval = 180 秒
    timeout  = 5 秒
    tolerance = 100 ms
    """

    return bool(
        re.fullmatch(
            r"\d+(?:,\d+){1,2}",
            token,
        )
    )


def get_refs(
    tokens: list[str],
) -> list[str]:
    return [
        token[2:]
        for token in tokens
        if token.startswith("[]")
    ]


def get_raw_regex(
    tokens: list[str],
) -> str | None:
    for token in tokens:
        if token.startswith("[]"):
            continue

        if is_url(token):
            continue

        if is_params(token):
            continue

        return token

    return None


def normalize_test_url(
    url: str,
) -> str:
    if (
        url
        == "http://www.gstatic.com/generate_204"
    ):
        return (
            "https://www.gstatic.com/"
            "generate_204"
        )

    return url


def get_test_url(
    tokens: list[str],
) -> str:
    for token in tokens:
        if is_url(token):
            return normalize_test_url(
                token
            )

    return (
        "https://www.gstatic.com/"
        "generate_204"
    )


def get_params(
    tokens: list[str],
) -> tuple[int, int, int]:

    interval = 180
    timeout_ms = 5000
    tolerance = 100

    for token in reversed(tokens):
        if not is_params(token):
            continue

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
            timeout_ms = (
                int(parts[1])
                * 1000
            )

        if (
            len(parts) >= 3
            and parts[2].isdigit()
        ):
            tolerance = int(
                parts[2]
            )

        break

    return (
        interval,
        timeout_ms,
        tolerance,
    )


# ============================================================
# 正则转换
#
# subconverter 当前大量使用：
#
# ^(?!.*(排除条件)).*(包含条件)
#
# Mihomo 原生转换成：
#
# filter: 包含条件
# exclude-filter: 排除条件
#
# 这样地区组、运营商组、普通池的纯净逻辑保持一致。
# ============================================================

def find_matching_paren(
    text: str,
    opening_index: int,
) -> int:
    """
    找到指定 "(" 对应的 ")"。
    同时忽略：
    - 转义字符
    - [...]
    """

    depth = 0
    escaped = False
    in_class = False

    for index in range(
        opening_index,
        len(text),
    ):
        char = text[index]

        if escaped:
            escaped = False
            continue

        if char == "\\":
            escaped = True
            continue

        if char == "[":
            in_class = True
            continue

        if (
            char == "]"
            and in_class
        ):
            in_class = False
            continue

        if in_class:
            continue

        if char == "(":
            depth += 1
            continue

        if char == ")":
            depth -= 1

            if depth == 0:
                return index

    raise ValueError(
        "正则括号不完整："
        + text
    )


def clean_include_regex(
    value: str,
) -> str | None:
    """
    subconverter 经常写：

    .*(香港|HK)
    或
    .*$
    或
    .*特殊.*

    Mihomo filter 本身就是匹配节点名称，
    因此可以去掉外围的 .*。
    """

    value = value.strip()

    if value in {
        "",
        ".*",
        ".*$",
        "^.*$",
    }:
        return None

    if value.startswith(".*"):
        value = value[2:]

    if value.endswith("$"):
        value = value[:-1]

    if value.endswith(".*"):
        value = value[:-2]

    if value.startswith("^"):
        value = value[1:]

    value = value.strip()

    if value in {
        "",
        ".*",
    }:
        return None

    return value


def assert_mihomo_regex(
    value: str | None,
    group_name: str,
) -> None:
    if not value:
        return

    unsupported = [
        "(?!",
        "(?=",
        "(?<=",
        "(?<!",
    ]

    for item in unsupported:
        if item in value:
            raise ValueError(
                f"{group_name} 转换后仍包含 "
                f"Mihomo 不适合直接使用的"
                f"前后瞻表达式：{item}\n"
                f"{value}"
            )

    # Go/RE2 不支持传统数字反向引用
    if re.search(
        r"\\[1-9]",
        value,
    ):
        raise ValueError(
            f"{group_name} 正则包含"
            f"反向引用，无法安全转换：\n"
            f"{value}"
        )


def convert_regex(
    raw: str | None,
    group_name: str,
) -> tuple[
    str | None,
    str | None,
]:
    """
    返回：

    (filter, exclude-filter)
    """

    if not raw:
        return None, None

    raw = raw.strip()

    # --------------------------------------------------------
    # 普通正则，没有负向前瞻
    # --------------------------------------------------------

    prefix = "^(?!.*("

    if not raw.startswith(prefix):
        include = clean_include_regex(
            raw
        )

        assert_mihomo_regex(
            include,
            group_name,
        )

        return include, None

    # --------------------------------------------------------
    # 解析：
    #
    # ^(?!.*(EXCLUDE)).*(INCLUDE)
    #
    # opening_index 就是 EXCLUDE 外层 "(" 的位置
    # --------------------------------------------------------

    opening_index = (
        len(prefix) - 1
    )

    closing_index = (
        find_matching_paren(
            raw,
            opening_index,
        )
    )

    # closing_index 后面必须还有一个 ")"
    # 用于关闭 (?! ... )
    lookahead_end = (
        closing_index + 1
    )

    if (
        lookahead_end
        >= len(raw)
        or raw[lookahead_end]
        != ")"
    ):
        raise ValueError(
            f"{group_name} 的负向前瞻"
            f"格式无法安全识别：\n"
            f"{raw}"
        )

    exclude = raw[
        opening_index + 1:
        closing_index
    ]

    remaining = raw[
        lookahead_end + 1:
    ]

    include = clean_include_regex(
        remaining
    )

    exclude = exclude.strip()

    if not exclude:
        exclude = None

    assert_mihomo_regex(
        include,
        group_name,
    )

    assert_mihomo_regex(
        exclude,
        group_name,
    )

    return (
        include,
        exclude,
    )


# ============================================================
# YAML 输出辅助
# ============================================================

def yaml_quote(
    value: str,
) -> str:
    """
    使用 YAML 单引号。

    好处：
    正则中的
    \\d
    \\s
    \\.
    不需要再次转义。
    """

    return (
        "'"
        + value.replace(
            "'",
            "''",
        )
        + "'"
    )


def emit_list(
    lines: list[str],
    key: str,
    values: list[str],
    indent: int = 4,
) -> None:

    prefix = " " * indent

    lines.append(
        f"{prefix}{key}:"
    )

    for value in values:
        lines.append(
            f"{prefix}  - "
            f"{yaml_quote(value)}"
        )


# ============================================================
# 配置完整性检查
#
# 以后如果再发生：
#
# ruleset=🎮 Steam
# custom_proxy_group=🧿 Steam
#
# 这种 emoji / 名称不一致，
# Action 会直接失败，不发布错误配置。
# ============================================================

def validate_config(
    rulesets: list[
        tuple[str, str]
    ],
    groups: list[Group],
) -> None:

    names = [
        group.name
        for group in groups
    ]

    duplicates = sorted(
        {
            name
            for name in names
            if names.count(name) > 1
        }
    )

    if duplicates:
        raise ValueError(
            "存在重复策略组："
            + ", ".join(
                duplicates
            )
        )

    name_set = set(names)

    # --------------------------------------------------------
    # ruleset 左侧必须有对应策略组
    # --------------------------------------------------------

    for policy, target in rulesets:
        if policy not in name_set:
            raise ValueError(
                "ruleset 指向不存在的"
                "策略组：\n"
                f"{policy} -> {target}"
            )

    # --------------------------------------------------------
    # custom_proxy_group 内引用必须存在
    # --------------------------------------------------------

    for group in groups:

        if group.kind not in {
            "select",
            "url-test",
            "fallback",
        }:
            raise ValueError(
                "暂不支持策略类型："
                f"{group.kind}\n"
                f"策略组：{group.name}"
            )

        for ref in get_refs(
            group.tokens
        ):
            if (
                ref not in name_set
                and ref
                not in BUILTIN_PROXIES
            ):
                raise ValueError(
                    f"策略组 {group.name} "
                    f"引用了不存在的对象："
                    f"{ref}"
                )

        # 顺便实际执行正则转换检查
        raw_regex = get_raw_regex(
            group.tokens
        )

        convert_regex(
            raw_regex,
            group.name,
        )


# ============================================================
# Proxy Provider
# ============================================================

def generate_proxy_provider(
    lines: list[str],
) -> None:

    lines.extend(
        [
            "proxy-providers:",
            f"  {PROVIDER_NAME}:",
            "    type: http",
            (
                "    url: "
                + yaml_quote(
                    AIRPORT_URL_PLACEHOLDER
                )
            ),
            (
                "    path: "
                "'./proxy_providers/"
                "Airport.yaml'"
            ),
            "    interval: 86400",
            "    header:",
            "      User-Agent:",
            "        - 'clash.meta'",
            "    health-check:",
            "      enable: true",
            (
                "      url: "
                "'https://www.gstatic.com/"
                "generate_204'"
            ),
            "      interval: 180",
            "      timeout: 5000",
            "      lazy: true",
            "      expected-status: 204",
            "",
        ]
    )


# ============================================================
# Proxy Group
# ============================================================

def generate_group(
    lines: list[str],
    group: Group,
) -> None:

    refs = get_refs(
        group.tokens
    )

    raw_regex = get_raw_regex(
        group.tokens
    )

    filter_regex, exclude_regex = (
        convert_regex(
            raw_regex,
            group.name,
        )
    )

    test_url = get_test_url(
        group.tokens
    )

    (
        interval,
        timeout,
        tolerance,
    ) = get_params(
        group.tokens
    )

    lines.append(
        "  - name: "
        + yaml_quote(
            group.name
        )
    )

    # ========================================================
    # SELECT
    # ========================================================

    if group.kind == "select":

        lines.append(
            "    type: select"
        )

        if refs:
            emit_list(
                lines,
                "proxies",
                refs,
                indent=4,
            )

        # select 同时包含：
        #
        # []自动组
        # +
        # 具体符合正则的节点
        #
        # 用 proxies + use 实现。
        if (
            filter_regex
            or exclude_regex
        ):
            lines.append(
                "    use:"
            )

            lines.append(
                "      - "
                + yaml_quote(
                    PROVIDER_NAME
                )
            )

            if filter_regex:
                lines.append(
                    "    filter: "
                    + yaml_quote(
                        filter_regex
                    )
                )

            if exclude_regex:
                lines.append(
                    "    exclude-filter: "
                    + yaml_quote(
                        exclude_regex
                    )
                )

        if (
            not refs
            and not filter_regex
            and not exclude_regex
        ):
            emit_list(
                lines,
                "proxies",
                [
                    "DIRECT",
                    "REJECT",
                ],
                indent=4,
            )

        return

    # ========================================================
    # URL-TEST
    # ========================================================

    if group.kind == "url-test":

        lines.extend(
            [
                "    type: url-test",
                "    use:",
                (
                    "      - "
                    + yaml_quote(
                        PROVIDER_NAME
                    )
                ),
            ]
        )

        if filter_regex:
            lines.append(
                "    filter: "
                + yaml_quote(
                    filter_regex
                )
            )

        if exclude_regex:
            lines.append(
                "    exclude-filter: "
                + yaml_quote(
                    exclude_regex
                )
            )

        lines.extend(
            [
                (
                    "    url: "
                    + yaml_quote(
                        test_url
                    )
                ),
                (
                    f"    interval: "
                    f"{interval}"
                ),
                (
                    f"    timeout: "
                    f"{timeout}"
                ),
                (
                    f"    tolerance: "
                    f"{tolerance}"
                ),
                "    lazy: true",
                (
                    "    expected-status: "
                    "204"
                ),
                (
                    "    empty-fallback: "
                    "REJECT"
                ),
            ]
        )

        return

    # ========================================================
    # FALLBACK
    # ========================================================
    if group.kind == "fallback":

        lines.append(
            "    type: fallback"
        )

        # fallback 可以有两种来源：
        #
        # 1. []策略组 / []节点引用
        #    例如：
        #    []低延迟-自动`[]所有-自动
        #
        # 2. Airport proxy-provider + 正则筛选
        #    例如：
        #    台湾 / 香港 / 日本等地区节点

        if refs:
            emit_list(
                lines,
                "proxies",
                refs,
                indent=4,
            )

        if (
            filter_regex
            or exclude_regex
        ):
            lines.append(
                "    use:"
            )
            lines.append(
                "      - "
                + yaml_quote(
                    PROVIDER_NAME
                )
            )

            if filter_regex:
                lines.append(
                    "    filter: "
                    + yaml_quote(
                        filter_regex
                    )
                )

            if exclude_regex:
                lines.append(
                    "    exclude-filter: "
                    + yaml_quote(
                        exclude_regex
                    )
                )

        # 完全没有引用和正则时，
        # 才使用 REJECT 兜底。
        if (
            not refs
            and not filter_regex
            and not exclude_regex
        ):
            emit_list(
                lines,
                "proxies",
                ["REJECT"],
                indent=4,
            )

        lines.extend(
            [
                (
                    "    url: "
                    + yaml_quote(
                        test_url
                    )
                ),
                (
                    f"    interval: "
                    f"{interval}"
                ),
                (
                    f"    timeout: "
                    f"{timeout}"
                ),
                "    lazy: true",
                (
                    "    expected-status: "
                    "204"
                ),
            ]
        )

        if (
            filter_regex
            or exclude_regex
        ):
            lines.append(
                "    empty-fallback: "
                "REJECT"
            )

        return


# ============================================================
# Rule Providers
# ============================================================

def generate_rule_providers(
    lines: list[str],
    rulesets: list[
        tuple[str, str]
    ],
) -> list[
    tuple[str, str, str]
]:

    lines.append(
        "rule-providers:"
    )

    mapping: list[
        tuple[str, str, str]
    ] = []

    number = 0

    for policy, target in rulesets:

        # []FINAL 不需要 provider
        if target.startswith("[]"):
            continue

        number += 1

        provider_id = (
            f"rule_{number:02d}"
        )

        mapping.append(
            (
                provider_id,
                policy,
                target,
            )
        )

        lines.extend(
            [
                (
                    f"  {provider_id}:"
                ),
                "    type: http",
                (
                    "    behavior: "
                    "classical"
                ),
                "    format: text",
                (
                    "    url: "
                    + yaml_quote(
                        target
                    )
                ),
                (
                    "    path: "
                    + yaml_quote(
                        "./rule_providers/"
                        f"{provider_id}.list"
                    )
                ),
                "    interval: 86400",

                # GitHub Raw 在部分网络
                # 直连可能不稳定。
                # 使用已经存在的国外策略组
                # 下载远程规则。
                (
                    "    proxy: "
                    + yaml_quote(
                        "🌍 国外"
                    )
                ),
            ]
        )

    lines.append("")

    return mapping


# ============================================================
# Rules
# ============================================================

def generate_rules(
    lines: list[str],
    rulesets: list[
        tuple[str, str]
    ],
    mapping: list[
        tuple[str, str, str]
    ],
) -> None:

    lines.append(
        "rules:"
    )

    map_index = 0
    final_policy = "DIRECT"

    for policy, target in rulesets:

        # ----------------------------------------------------
        # FINAL
        # ----------------------------------------------------

        if target == "[]FINAL":
            final_policy = policy
            continue

        # ----------------------------------------------------
        # 暂不静默处理其他 [] 内联规则
        # ----------------------------------------------------

        if target.startswith("[]"):
            raise ValueError(
                "发现尚未支持的"
                "内联 ruleset：\n"
                f"ruleset="
                f"{policy},{target}"
            )

        (
            provider_id,
            mapped_policy,
            mapped_target,
        ) = mapping[
            map_index
        ]

        map_index += 1

        if (
            mapped_policy != policy
            or mapped_target != target
        ):
            raise ValueError(
                "ruleset 映射顺序异常"
            )

        lines.append(
            "  - "
            + yaml_quote(
                "RULE-SET,"
                f"{provider_id},"
                f"{policy}"
            )
        )

    lines.append(
        "  - "
        + yaml_quote(
            f"MATCH,{final_policy}"
        )
    )

    lines.append("")


# ============================================================
# 生成完整 Android Mihomo 模板
# ============================================================

def generate_android(
    rulesets: list[
        tuple[str, str]
    ],
    groups: list[Group],
) -> str:

    lines: list[str] = [
        "# ==================================================",
        "# AUTO-GENERATED FILE",
        "# Source: Clash-Li.ini",
        "#",
        "# 请勿手工修改此文件。",
        "# 修改 Clash-Li.ini 后由 GitHub Actions 自动生成。",
        "# ==================================================",
        "",
        "mixed-port: 7890",
        "allow-lan: false",
        "mode: rule",
        "log-level: info",
        "ipv6: true",
        "unified-delay: true",
        "tcp-concurrent: true",
        "",
        "profile:",
        "  store-selected: true",
        "  store-fake-ip: true",
        "",
    ]

    # --------------------------------------------------------
    # 机场订阅
    # --------------------------------------------------------

    generate_proxy_provider(
        lines
    )

    # --------------------------------------------------------
    # 策略组
    # --------------------------------------------------------

    lines.append(
        "proxy-groups:"
    )

    for group in groups:
        generate_group(
            lines,
            group,
        )

    lines.append("")

    # --------------------------------------------------------
    # 远程 list
    # --------------------------------------------------------

    mapping = (
        generate_rule_providers(
            lines,
            rulesets,
        )
    )

    # --------------------------------------------------------
    # 分流顺序
    # --------------------------------------------------------

    generate_rules(
        lines,
        rulesets,
        mapping,
    )

    return "\n".join(lines)


# ============================================================
# Main
# ============================================================

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

    validate_config(
        rulesets,
        groups,
    )

    OUTPUT.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    content = generate_android(
        rulesets,
        groups,
    )

    OUTPUT.write_text(
        content,
        encoding="utf-8",
    )

    print(
        "================================"
    )

    print(
        "Android Mihomo template generated"
    )

    print(
        "Source:",
        SOURCE_INI.relative_to(
            ROOT
        ),
    )

    print(
        "Output:",
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

    print(
        "Airport placeholder:",
        AIRPORT_URL_PLACEHOLDER,
    )

    print(
        "================================"
    )


if __name__ == "__main__":
    main()
