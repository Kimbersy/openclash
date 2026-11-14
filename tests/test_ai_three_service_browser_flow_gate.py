"""Offline, privacy-safe acceptance for actual AI website flow routing.

Never generates a real authenticated account session or independently inspects
router connection logs. Synthetic green is not real BUSINESS_VERIFIED.
"""
from datetime import datetime, timezone
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ai_three_service_browser_flow_gate import APP_HOSTS, CHECKS, GOOGLE_LOGIN, GEMINI_API_HOSTS, check_browser_workflow_receipt
from ai_service_stability_dry_run import WORKFLOW_TASKS, business_verified

NOW = datetime(2026, 11, 14, 2, 0, tzinfo=timezone.utc)
FP = "b" * 64
SESSION = "TEST_SESSION_0001"


def record(service):
    app = sorted(APP_HOSTS[service])[0]
    stages = [("app", app), ("answer", app)]
    if service == "notebooklm":
        stages = [("app", "notebook.google.com"),
                  ("source_import", "notebooklm-pa.googleapis.com"),
                  ("answer", "notebook.google.com"),
                  ("auth", GOOGLE_LOGIN)]
    return {
        "service": service, "method": "user_interactive_workflow",
        "node_fingerprint": FP, "observed_at": NOW.isoformat(),
        "session_tag": SESSION, "redirect_state": "app",
        "http_only": False,
        "login_redirect_observed": service == "notebooklm",
        "checks": {key: True for key in CHECKS[service]},
        "citation_checked_against_source": True,
        "routes": [{"stage": stage, "host": host, "session_tag": SESSION,
                    "ai_parent": "🤖 AI", "node_fingerprint": FP,
                    "exit_consistent": True}
                   for stage, host in stages],
    }


class AiFlowRoutingAcceptance(unittest.TestCase):
    def check(self, receipt, service="notebooklm"):
        result = check_browser_workflow_receipt(
            receipt, service=service, expected_node_fp=FP, now=NOW,
        )
        self.assertFalse(result["business_verified"])
        self.assertFalse(result["allow_switch"])
        self.assertFalse(result["live_writes"])
        self.assertNotIn(SESSION, repr(result))
        self.assertNotIn(FP, repr(result))
        return result

    def test_real_pool_requirements_never_weaker_than_real_browser_checklist(self):
        # Otherwise a synthetic browser gate might reject an incomplete NotebookLM
        # workflow while the global/region pool still admits that same node.
        self.assertEqual(set(WORKFLOW_TASKS), set(CHECKS))
        for service in WORKFLOW_TASKS:
            self.assertEqual(set(WORKFLOW_TASKS[service]), set(CHECKS[service]))
            self.assertIn("route_consistent", WORKFLOW_TASKS[service])
        self.assertIn("citation_checked", WORKFLOW_TASKS["notebooklm"])
        self.assertIn("signed_in", WORKFLOW_TASKS["notebooklm"])

    def test_gemini_actual_published_exact_api_hosts_do_not_false_fail(self):
        # Browser answer often uses Gemini's dedicated backends, not just
        # gemini.google.com; never expand public Google suffix routing to fix.
        for host in GEMINI_API_HOSTS:
            receipt = record("gemini")
            receipt["routes"][1]["host"] = host
            r = self.check(receipt, "gemini")
            self.assertEqual(r["decision"], "ROUTING_AND_WORKFLOW_RECEIPT_CANDIDATE_ONLY")
        receipt = record("gemini")
        receipt["routes"][1]["host"] = "unreviewed-shared.googleapis.com"
        self.assertEqual(self.check(receipt, "gemini")["decision"],
                         "HOLD_UNREVIEWED_DEPENDENCY")

    def test_missing_same_exit_claim_blocks_even_if_route_rows_are_green(self):
        for service in ("chatgpt", "gemini", "notebooklm"):
            receipt = record(service)
            receipt["checks"].pop("route_consistent")
            self.assertEqual(self.check(receipt, service)["decision"],
                             "HOLD_INCOMPLETE_REAL_BUSINESS_WORKFLOW")

    def test_all_three_complete_synthetic_flows_still_not_business_verified(self):
        for service in ("chatgpt", "gemini", "notebooklm"):
            r = self.check(record(service), service)
            self.assertEqual(r["decision"], "ROUTING_AND_WORKFLOW_RECEIPT_CANDIDATE_ONLY")
            self.assertTrue(r["routing_consistency_candidate"])

    def test_notebooklm_landing_or_unsupported_even_http200_is_not_business(self):
        for status in ("location=unsupported", "marketing_landing", "access_denied"):
            receipt = record("notebooklm")
            receipt["redirect_state"] = status
            receipt["http_code"] = 200
            self.assertEqual(self.check(receipt)["decision"],
                             "HOLD_NOTEBOOK_ACCESS_GATE_OR_LANDING")
        receipt = record("notebooklm")
        receipt["routes"][0]["host"] = "notebook.google"
        self.assertEqual(self.check(receipt)["decision"],
                         "HOLD_NOTEBOOK_ACCESS_GATE_OR_LANDING")

    def test_notebooklm_signedin_workspace_import_answer_and_citation_required(self):
        for check in CHECKS["notebooklm"]:
            receipt = record("notebooklm")
            receipt["checks"][check] = False
            self.assertEqual(self.check(receipt)["decision"],
                             "HOLD_INCOMPLETE_REAL_BUSINESS_WORKFLOW")
        receipt = record("notebooklm")
        receipt["citation_checked_against_source"] = False
        self.assertEqual(self.check(receipt)["decision"],
                         "HOLD_NOTEBOOK_SOURCE_CITATION_NOT_CONFIRMED")
        receipt = record("notebooklm")
        receipt["routes"] = [event for event in receipt["routes"]
                             if event["stage"] != "source_import"]
        self.assertEqual(self.check(receipt)["decision"],
                         "HOLD_INCOMPLETE_ROUTE_STAGES")

    def test_split_google_login_or_import_egress_cannot_qualify(self):
        for idx in range(4):
            receipt = record("notebooklm")
            receipt["routes"][idx]["exit_consistent"] = False
            self.assertEqual(self.check(receipt)["decision"],
                             "HOLD_SPLIT_EGRESS_OR_NON_AI_ROUTE")
        receipt = record("notebooklm")
        receipt["routes"][1]["ai_parent"] = "🌍 国外"
        self.assertEqual(self.check(receipt)["decision"],
                         "HOLD_SPLIT_EGRESS_OR_NON_AI_ROUTE")
        receipt = record("notebooklm")
        receipt["routes"][1]["node_fingerprint"] = "c" * 64
        self.assertEqual(self.check(receipt)["decision"],
                         "HOLD_SPLIT_EGRESS_OR_NON_AI_ROUTE")
        receipt = record("notebooklm")
        receipt["routes"] = [x for x in receipt["routes"] if x["stage"] != "auth"]
        self.assertEqual(self.check(receipt)["decision"],
                         "HOLD_LOGIN_ROUTE_NOT_CAPTURED")

    def test_malformed_or_http_blocking_browser_receipts_do_not_qualify(self):
        for patch, status in (
            ({"redirect_state": "unknown"}, "HOLD_UNVERIFIED_OR_FAILED_BROWSER_APP"),
            ({"http_code": 403}, "HOLD_UNVERIFIED_OR_FAILED_BROWSER_APP"),
            ({"http_code": 429}, "HOLD_UNVERIFIED_OR_FAILED_BROWSER_APP"),
            ({"network_error": True}, "HOLD_UNVERIFIED_OR_FAILED_BROWSER_APP"),
            ({"login_redirect_observed": "yes"}, "HOLD_INVALID_BROWSER_FLAGS"),
        ):
            receipt = record("notebooklm")
            receipt.update(patch)
            self.assertEqual(self.check(receipt)["decision"], status)
        receipt = record("notebooklm")
        receipt["routes"][-1]["host"] = "auth.openai.com"
        self.assertEqual(self.check(receipt)["decision"], "HOLD_UNEXPECTED_AUTH_HOST")

    def test_http_200_untrusted_automation_stale_time_and_wrong_node_hold(self):
        changes = (
            ({"http_only": True}, "HOLD_HTTP_ONLY_OR_UNTRUSTED_METHOD"),
            ({"method": "curl_200"}, "HOLD_HTTP_ONLY_OR_UNTRUSTED_METHOD"),
            ({"node_fingerprint": "c" * 64}, "HOLD_WRONG_SERVICE_OR_NODE"),
            ({"observed_at": "2026-01-01T00:00:00Z"}, "HOLD_TIMESTAMP"),
        )
        for edits, want in changes:
            receipt = record("notebooklm")
            receipt.update(edits)
            self.assertEqual(self.check(receipt)["decision"], want)

    def test_notebooklm_entry_without_real_workflow_stays_unknown(self):
        proof = {"status": "BUSINESS_VERIFIED", "fingerprint": FP,
                 "method": "homepage_http_200",
                 "observed_at": NOW.isoformat(),
                 "expires_at": "2026-11-15T02:00:00Z",
                 "checks": {"workspace_opened": True, "source_imported": False,
                            "question_answered": False}}
        self.assertFalse(business_verified(proof, service="notebooklm", fingerprint=FP, now=NOW))
        receipt = record("notebooklm")
        receipt["http_only"] = True
        self.assertFalse(self.check(receipt)["routing_consistency_candidate"])

    def test_existing_rules_cover_apps_without_proxying_all_google_services(self):
        rules = set((ROOT / "list/AI.list").read_text(encoding="utf-8").splitlines())
        for required in (
            "DOMAIN-SUFFIX,chatgpt.com", "DOMAIN-SUFFIX,openai.com",
            "DOMAIN-SUFFIX,gemini.google.com", "DOMAIN,accounts.google.com",
            "DOMAIN-SUFFIX,notebook.google.com",
            "DOMAIN-SUFFIX,notebooklm.google.com",
            "DOMAIN,notebooklm-pa.googleapis.com",
            "DOMAIN,notebooklm.googleapis.com",
            "DOMAIN,contribution.usercontent.google.com",
        ):
            self.assertIn(required, rules)
        for unsafe in ("DOMAIN-SUFFIX,google.com",
                       "DOMAIN-SUFFIX,googleapis.com",
                       "DOMAIN-SUFFIX,gstatic.com",
                       "DOMAIN,notebook.google"):
            self.assertNotIn(unsafe, rules)
        ini = (ROOT / "Clash-Li.ini").read_text(encoding="utf-8")
        ai = ini.index("ruleset=🤖 AI,")
        self.assertLess(ai, ini.index("ruleset=🌍 国外,"))
        self.assertLess(ai, ini.index("ruleset=🏠 国内,"))
        self.assertIn("custom_proxy_group=🤖 AI"+chr(96)+"select"+chr(96), ini)
        self.assertIn("custom_proxy_group=🏰 Disney+"+chr(96)+"select"+chr(96), ini)

    def test_no_shared_config_changes_in_this_feature(self):
        self.assertTrue((ROOT / "tests/test_shared_three_client_contract.py").exists())


if __name__ == "__main__":
    unittest.main()
