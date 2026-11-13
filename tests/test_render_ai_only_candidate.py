"""AI-only cross-client candidate: non-AI routes must remain exactly as before."""
import pathlib
import sys
import tempfile
import unittest
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import generate_android
import generate_shadowrocket
import render_ai_only_candidate as ai
import render_verified_candidate as existing

BASE = (ROOT / "Clash-Li.ini").read_text(encoding="utf-8")


def pools(countries=None):
    countries = countries if countries is not None else {"TW": ["台湾01", "台湾(02)"], "US": ["美国 01"]}
    return {"all_services": countries,
            "per_service": {svc: {cc: list(names) for cc, names in countries.items()}
                            for svc in ai.SERVICES}}


def build(base=BASE, private_pools=None):
    return ai.build_ai_only_candidate(
        base,
        private_pools if private_pools is not None else pools(),
        source_coverage_verified=True,
        active_runtime_confirmed=True,
        platform_business_verified=True,
    )


def config_result(source):
    with tempfile.TemporaryDirectory() as tmp:
        ini = pathlib.Path(tmp) / "candidate.ini"
        ini.write_text(source, encoding="utf-8")
        android, shadow = existing.generate_both(str(ini))
    return android, shadow


class AiOnlyCandidateTests(unittest.TestCase):
    def test_missing_runtime_or_business_evidence_fails_closed(self):
        for kwargs in ({}, {"source_coverage_verified": True, "active_runtime_confirmed": True},
                       {"source_coverage_verified": True, "platform_business_verified": True},
                       {"active_runtime_confirmed": True, "platform_business_verified": True}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                ai.build_ai_only_candidate(BASE, pools(), **kwargs)

    def test_empty_platform_qualification_preserves_original_exactly(self):
        src, summary = build(private_pools=pools({}))
        self.assertEqual(src, BASE)
        self.assertEqual(summary["status"], "NO_BUSINESS_VERIFIED_POOL")

    def test_partial_service_qualification_does_not_admit_node(self):
        data = pools({"TW": ["台湾01"]})
        data["per_service"]["notebooklm"]["TW"] = []
        with self.assertRaisesRegex(ValueError, "three-platform"):
            build(private_pools=data)

    def test_reject_bad_provenance_structure_and_labels(self):
        for data in ({"all_services": {"TW": ["台湾01"]}},
                     {"per_service": {}, "all_services": {"TW": ["台湾01"]}},
                     pools({"taiwan": ["台湾01"]}),
                     pools({"TW": ["台湾01", "台湾01"]}),
                     pools({"TW": ["bad,comma"]}),
                     pools({"TW": ["bad`name"]}),
                     pools({"TW": ["bad\\slash"]}),
                     pools({"TW": ["bad\nnewline"]}),
                     pools({"TW": ["台湾01"], "US": ["台湾01"]})):
            with self.subTest(data=repr(data)[:150]), self.assertRaises(ValueError):
                build(private_pools=data)

    def test_non_ai_ini_lines_and_rule_order_unchanged(self):
        new, meta = build()
        base_lines = BASE.splitlines()
        new_lines = new.splitlines()
        new_non_ai = [l for l in new_lines if not l.startswith("custom_proxy_group=🤖 AI`")
                      and not l.startswith("custom_proxy_group=🛡️AI·")
                      and not l.startswith("; PRIVATE AI-ONLY VERIFIED CANDIDATE.")]
        base_non_ai = [l for l in base_lines if not l.startswith("custom_proxy_group=🤖 AI`")]
        self.assertEqual(base_non_ai, new_non_ai)
        self.assertEqual([l for l in base_lines if l.startswith("ruleset=")],
                         [l for l in new_lines if l.startswith("ruleset=")])
        self.assertEqual(meta, {"status": "PRIVATE_MANUAL_CANDIDATE_ONLY",
                                "countries": 2, "nodes": 3})

    def test_one_extension_to_original_ai_members_only(self):
        new, _ = build()
        base_ai = next(l for l in BASE.splitlines() if l.startswith("custom_proxy_group=🤖 AI`"))
        candidate_ai = next(l for l in new.splitlines() if l.startswith("custom_proxy_group=🤖 AI`"))
        self.assertTrue(candidate_ai.startswith(base_ai))
        self.assertIn("`[]" + ai.ALL, candidate_ai)
        self.assertIn("`[]" + ai.PREFIX + "TW", candidate_ai)
        self.assertIn("`[]" + ai.PREFIX + "US", candidate_ai)
        self.assertIn("custom_proxy_group=" + ai.ALL + "`select`", new)
        self.assertNotIn("custom_proxy_group=" + ai.ALL + "`url-test`", new)
        self.assertNotIn("custom_proxy_group=" + ai.ALL + "`fallback`", new)

    def test_all_regions_are_real_exit_only_and_anchored(self):
        import re
        new, _ = build(private_pools=pools({"TW": ["台湾01"], "GB": ["英国1"]}))
        expected = ai.PREFIX + "TW" + "`select`" + existing.literal_filter(["台湾01"])
        self.assertIn(expected, new)
        self.assertIn(ai.PREFIX + "GB", new)
        p = existing.literal_filter(["台湾01"])
        self.assertTrue(re.search(p, "台湾01"))
        self.assertFalse(re.search(p, "台湾012"))

    def test_qualified_group_cross_client_generator_smoke_and_non_ai_byte_equivalence(self):
        import yaml
        old_android, old_shadow = config_result(BASE)
        new, _ = build()
        android, shadow = config_result(new)
        old_yaml = yaml.safe_load(old_android)
        new_yaml = yaml.safe_load(android)
        self.assertEqual(old_yaml["rules"], new_yaml["rules"])
        self.assertEqual(old_yaml["rule-providers"], new_yaml["rule-providers"])
        self.assertEqual(old_yaml["proxy-providers"], new_yaml["proxy-providers"])
        old_groups = {g["name"]: g for g in old_yaml["proxy-groups"]}
        new_groups = {g["name"]: g for g in new_yaml["proxy-groups"]}
        for key, item in old_groups.items():
            if key == "🤖 AI":
                self.assertEqual(item["proxies"], new_groups[key]["proxies"][:len(item["proxies"])])
                continue
            self.assertEqual(item, new_groups[key], key)
        self.assertEqual(new_groups[ai.ALL]["type"], "select")
        self.assertIn("__AIRPORT_URL__", android)
        # Every existing Shadowrocket line, except the AI select line, must
        # survive literally and in original order after candidate generation.
        original_lines = old_shadow.splitlines()
        next_lines = shadow.splitlines()
        normal = [line for line in next_lines if not line.startswith("🤖 AI = select")
                  and not line.startswith(ai.ALL + " = select")
                  and not line.startswith(ai.PREFIX)]
        expected = [line for line in original_lines if not line.startswith("🤖 AI = select")]
        self.assertEqual(expected, normal)

    def test_existing_dynamic_candidate_refuses_duplicate_group_install(self):
        new, _ = build()
        with self.assertRaisesRegex(ValueError, "existing AI qualified"):
            build(base=new)

    def test_missing_parent_or_double_parent_fails(self):
        for source in (BASE.replace("custom_proxy_group=🤖 AI`select`", "custom_proxy_group=🤖 AI`url-test`"),
                       BASE + next(l for l in BASE.splitlines()
                                   if l.startswith("custom_proxy_group=🤖 AI`")) + "\n"):
            with self.assertRaisesRegex(ValueError, "exactly once"):
                build(base=source)


if __name__ == "__main__":
    unittest.main()
