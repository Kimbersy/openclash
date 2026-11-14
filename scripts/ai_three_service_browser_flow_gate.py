#!/usr/bin/env python3
"""OFFLINE AI browser workflow routing receipt gate, especially NotebookLM.

Inputs describe an AUTHORIZED real browser session; do not paste cookies,
URLs, prompt content, notebooks, credential strings, or IPs into public Git.
This is an untrusted-receipt structural checker, not a browser driver or
cryptographic attestor. A green structure alone NEVER grants BUSINESS_VERIFIED,
switch permission, install approval, or a successful real-router receipt.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import re
from typing import Any

APP_HOSTS = {
    "chatgpt": frozenset(("chatgpt.com",)),
    "gemini": frozenset(("gemini.google.com",)),
    "notebooklm": frozenset(("notebook.google.com", "notebooklm.google.com")),
}
# Keep all business gate check names aligned with qualified_pool:
# synthetic browser route checks must not be silently skipped by pool builder.
CHECKS = {
    "chatgpt": ("signed_in", "prompt_answered", "stream_completed", "route_consistent"),
    "gemini": ("signed_in", "prompt_answered", "route_consistent"),
    "notebooklm": (
        "signed_in", "workspace_opened", "source_imported",
        "question_answered", "citation_checked", "route_consistent",
    ),
}
STAGES = {
    "chatgpt": ("app", "answer"),
    "gemini": ("app", "answer"),
    "notebooklm": ("app", "source_import", "answer"),
}
NOTEBOOK_API_HOSTS = frozenset((
    "notebooklm-pa.googleapis.com", "notebooklm.googleapis.com",
    "contribution.usercontent.google.com",
))
GOOGLE_LOGIN = "accounts.google.com"
LANDING_ONLY = frozenset(("notebook.google", "notebooklm.google"))


def check_browser_workflow_receipt(
    receipt: Any, *, service: str, expected_node_fp: str,
    now: datetime,
) -> dict[str, object]:
    """Return ANONYMOUS structured safety result (not a BUSINESS_VERIFIED token)."""
    def stop(reason: str) -> dict[str, object]:
        return {
            "decision": reason, "routing_consistency_candidate": False,
            "business_verified": False, "allow_switch": False,
            "live_writes": False,
        }

    if service not in CHECKS or now.tzinfo is None:
        return stop("HOLD_INVALID_INPUT")
    if not isinstance(expected_node_fp, str) or re.fullmatch(r"[a-f0-9]{64}", expected_node_fp) is None:
        return stop("HOLD_INVALID_INPUT")
    if not isinstance(receipt, dict):
        return stop("HOLD_NO_REAL_BROWSER_RECEIPT")
    # Landing and unsupported redirects can return HTTP 200 but never mean
    # successful personal notebook access; do not infer a specific cause.
    if receipt.get("redirect_state") in ("location=unsupported", "marketing_landing", "access_denied"):
        return stop("HOLD_NOTEBOOK_ACCESS_GATE_OR_LANDING")
    if receipt.get("redirect_state") != "app" or receipt.get("http_code") in (403, 429, 451):
        return stop("HOLD_UNVERIFIED_OR_FAILED_BROWSER_APP")
    if receipt.get("network_error") is True:
        return stop("HOLD_UNVERIFIED_OR_FAILED_BROWSER_APP")
    if (type(receipt.get("login_redirect_observed")) is not bool
            or type(receipt.get("http_only")) is not bool):
        return stop("HOLD_INVALID_BROWSER_FLAGS")
    if receipt.get("http_only") is True or receipt.get("method") != "user_interactive_workflow":
        return stop("HOLD_HTTP_ONLY_OR_UNTRUSTED_METHOD")
    if receipt.get("service") != service or receipt.get("node_fingerprint") != expected_node_fp:
        return stop("HOLD_WRONG_SERVICE_OR_NODE")
    at = receipt.get("observed_at")
    if not isinstance(at, str):
        return stop("HOLD_TIMESTAMP")
    try:
        when = datetime.fromisoformat(at.replace("Z", "+00:00"))
    except ValueError:
        return stop("HOLD_TIMESTAMP")
    if when.tzinfo is None or not timedelta(0) <= now - when.astimezone(timezone.utc) <= timedelta(hours=24):
        return stop("HOLD_TIMESTAMP")
    checks = receipt.get("checks")
    if not isinstance(checks, dict) or not all(checks.get(name) is True for name in CHECKS[service]):
        return stop("HOLD_INCOMPLETE_REAL_BUSINESS_WORKFLOW")

    routes = receipt.get("routes")
    if not isinstance(routes, list) or not routes or any(not isinstance(row, dict) for row in routes):
        return stop("HOLD_NO_ROUTE_CHAIN")
    stages = set()
    auth_seen = False
    consistent_session = receipt.get("session_tag")
    # Opaque private session tag is only a consistency signal; no cookies.
    if not isinstance(consistent_session, str) or not re.fullmatch(r"[A-Za-z0-9_-]{8,48}", consistent_session):
        return stop("HOLD_SESSION_PROVENANCE")
    app_hosts = APP_HOSTS[service]
    for event in routes:
        stage, host = event.get("stage"), event.get("host")
        if not isinstance(host, str) or not host or host != host.lower() or "/" in host or "?" in host:
            return stop("HOLD_ROUTE_HOST")
        if service == "notebooklm" and host in LANDING_ONLY:
            return stop("HOLD_NOTEBOOK_ACCESS_GATE_OR_LANDING")
        if (event.get("session_tag") != consistent_session
                or event.get("node_fingerprint") != expected_node_fp
                or event.get("ai_parent") != "🤖 AI"
                or event.get("exit_consistent") is not True):
            return stop("HOLD_SPLIT_EGRESS_OR_NON_AI_ROUTE")
        if stage == "auth":
            allowed_auth = ((GOOGLE_LOGIN, "auth.openai.com", "chatgpt.com")
                            if service == "chatgpt" else (GOOGLE_LOGIN,))
            if host not in allowed_auth:
                return stop("HOLD_UNEXPECTED_AUTH_HOST")
            auth_seen = True
        elif stage == "app":
            if host not in app_hosts:
                return stop("HOLD_WRONG_APP_HOST")
            stages.add("app")
        elif stage in ("source_import", "answer"):
            valid = app_hosts | NOTEBOOK_API_HOSTS if service == "notebooklm" else app_hosts
            if host not in valid:
                return stop("HOLD_UNREVIEWED_DEPENDENCY")
            stages.add(stage)
        elif stage == "dependency":
            # Inspect unexpected Google shared hosts before ever touching
            # global googleapis.com/gstatic.com routing rules.
            stages.add("dependency")
        else:
            return stop("HOLD_UNREVIEWED_ROUTE_STAGE")
    if not set(STAGES[service]).issubset(stages):
        return stop("HOLD_INCOMPLETE_ROUTE_STAGES")
    if receipt.get("login_redirect_observed") is True and not auth_seen:
        return stop("HOLD_LOGIN_ROUTE_NOT_CAPTURED")
    if service == "notebooklm" and receipt.get("citation_checked_against_source") is not True:
        return stop("HOLD_NOTEBOOK_SOURCE_CITATION_NOT_CONFIRMED")
    return {
        "decision": "ROUTING_AND_WORKFLOW_RECEIPT_CANDIDATE_ONLY",
        "routing_consistency_candidate": True,
        "business_verified": False,  # actual independent human/router signoff pending
        "allow_switch": False,
        "live_writes": False,
    }


if __name__ == "__main__":
    raise SystemExit("Pure offline receipt validation only; no browser or router operation.")
