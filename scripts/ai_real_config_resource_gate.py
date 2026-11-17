#!/usr/bin/env python3
"""Pure offline classification of external-resource hazards in a candidate
Mihomo private config. NEVER authorizes executing mihomo -t on real data.
No reads, writes, requests, subprocesses or secret-bearing diagnostics.
"""
from __future__ import annotations
import re

MAX_PROVIDERS = 2000
RESOURCE_TOKENS = re.compile(
    r"(?i)(?:geosite:|rule-set:|geoip:|(?:^|[,(:])(?:GEOIP|GEOSITE)\s*[,(:])"
)

def audit_resources(config: object) -> dict:
    def result(code: str, **extra: int | bool) -> dict:
        return {"decision": code, "may_invoke_mihomo": False,
                "can_make_network_request": False, "production_writes": False,
                "user_secrets_returned": False, **extra}

    if not isinstance(config, dict):
        return result("HOLD_CONFIG_LAYOUT")
    providers = config.get("rule-providers")
    if not isinstance(providers, dict) or not 1 <= len(providers) <= MAX_PROVIDERS:
        return result("HOLD_RULE_PROVIDER_LAYOUT")
    if any(not isinstance(k, str) or not isinstance(v, dict) or v.get("type") != "http"
           for k, v in providers.items()):
        return result("HOLD_RULE_PROVIDER_SOURCE")
    if config.get("proxy-providers") not in (None, {}):
        return result("HOLD_PROXY_PROVIDERS")
    groups = config.get("proxy-groups")
    if not isinstance(groups, list) or any(not isinstance(x, dict) for x in groups):
        return result("HOLD_GROUP_LAYOUT")
    if any(g.get("use") or g.get("include-all") for g in groups):
        return result("HOLD_PROXY_PROVIDER_GROUP_REFERENCE")
    rules = config.get("rules")
    if not isinstance(rules, list) or not all(isinstance(x, str) for x in rules):
        return result("HOLD_RULES_LAYOUT")
    if any(re.search(r"(?i)(?:^|[,(:])(?:GEOIP|GEOSITE)\s*[,(:]", x) for x in rules):
        return result("HOLD_GEO_RULE_REFERENCE")
    if config.get("geodata-mode") is True or config.get("geo-auto-update") is True:
        return result("HOLD_GEO_MODE_CHANGED")
    if "geox-url" not in config:
        return result("HOLD_GEO_SOURCE_CHANGED")
    if not isinstance(config["geox-url"], dict):
        return result("HOLD_GEO_URL_LAYOUT")
    dns = config.get("dns", {})
    if not isinstance(dns, dict):
        return result("HOLD_DNS_LAYOUT")
    fbf = dns.get("fallback-filter")
    if isinstance(fbf, dict) and (fbf.get("geoip") is True or fbf.get("geoip-code")):
        return result("HOLD_DNS_GEO_FALLBACK")

    def nested_geo(value: object, depth: int = 0) -> bool:
        if depth > 28:
            return True
        if isinstance(value, dict):
            return any(nested_geo(k, depth + 1) or nested_geo(v, depth + 1)
                       for k, v in value.items())
        if isinstance(value, list):
            return any(nested_geo(v, depth + 1) for v in value)
        return isinstance(value, str) and bool(RESOURCE_TOKENS.search(value))

    # geox-url contains download origins, not proof of a completed download.
    # Provider URL values are not needed to detect configuration references.
    rest = {k: v for k, v in config.items()
            if k not in ("geox-url", "rule-providers")}
    if nested_geo(rest):
        return result("HOLD_NESTED_GEO_REFERENCE")
    if any(k in config for k in ("script", "external-ui-url", "sub-rules")):
        return result("HOLD_OTHER_EXTERNAL_RESOURCE")
    # Even if no reference is found, downloaded resources or DNS init could
    # still occur when the REAL parser runs. Fail closed without a separately
    # verified, network-denied sandbox and complete local dependency plan.
    return result("HOLD_NETWORK_ISOLATION_UNPROVEN",
                  cached_http_rule_providers=len(providers),
                  custom_geo_url_present=True,
                  geo_auto_update_enabled=False)
