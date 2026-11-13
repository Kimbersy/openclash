"""Hard gate: never silently ship router-only AI changes through shared converter.

These hashes pin the *currently published* common files. Updating a hash
requires separately recorded router, Android Clash Mate and iOS Shadowrocket
client-format approvals / smoke receipts. CI here cannot emulate the phones.
"""
from __future__ import annotations
import hashlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PUBLISHED_COMMON_GIT_BLOBS = {
    "Clash-Li.ini": "403407184f8e12fa198fa209e86c66ebdb33387f",
    "list/AI.list": "1eebe4b5b3b4a82be7ae55ecbd7f22e6b2407046",
    "generated/Clash-Meta-Android.template.yaml":
        "51cc203c454c883a05a376c835977418f037b404",
}


def git_blob_id(path: Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\\0".encode().replace(b"\\0", b"\\x00") + raw).hexdigest()


class SharedThreeClientContract(unittest.TestCase):
    def test_common_conversion_files_have_not_changed(self):
        # This is a change-release safety gate, not an Android/iOS app parser.
        for name, expected in PUBLISHED_COMMON_GIT_BLOBS.items():
            with self.subTest(file=name):
                self.assertEqual(
                    git_blob_id(ROOT / name), expected,
                    "Shared converter changed: do not publish before three-client review",
                )

    def test_existing_ai_group_and_domain_routing_are_kept(self):
        source = (ROOT / "Clash-Li.ini").read_text(encoding="utf-8")
        self.assertIn(
            "ruleset=🤖 AI,https://raw.githubusercontent.com/kimbersy/openclash/main/list/AI.list",
            source,
        )
        self.assertIn("custom_proxy_group=🤖 AI`select`", source)
        for existing in ("🏰 Disney+", "📺 流媒体", "🏠 国内", "💻 GitHub"):
            self.assertIn(existing, source)

    def test_android_generated_template_has_no_router_monitor(self):
        template = (ROOT / "generated/Clash-Meta-Android.template.yaml").read_text(encoding="utf-8")
        self.assertIn("Source: Clash-Li.ini", template)
        self.assertIn("__AIRPORT_URL__", template)
        self.assertIn("- name: '🤖 AI'", template)
        for forbidden in (
            "ai_dynamic_refresh_planner",
            "AI_DYNAMIC_MONITOR",
            "router-only-control",
            "SOURCE_SNAPSHOT_SHA256_PREFIX16",
        ):
            self.assertNotIn(forbidden, template)

    def test_shared_ai_rules_do_not_install_unapproved_notebook_host(self):
        # Preserve main baseline. Future notebook.google routing, if needed,
        # must be introduced via proven router-only local overlay.
        rules = (ROOT / "list/AI.list").read_text(encoding="utf-8").splitlines()
        self.assertIn("DOMAIN-SUFFIX,notebook.google.com", rules)
        self.assertIn("DOMAIN,accounts.google.com", rules)
        self.assertNotIn("DOMAIN,notebook.google", rules)


if __name__ == "__main__":
    unittest.main()
