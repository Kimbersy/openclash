"""Deployment barrier for iStoreOS's proven minimal Ruby runtime.

Actual 2026-11-14 13:55 TTYD: psych loaded; timeout raised LoadError
BEFORE any router checks. Ubuntu Actions Ruby is not OpenWrt evidence.

Every new user-facing router script must be added here with known dependencies
or held until they have been independently verified on the real device.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
ADMISSION = ROOT / "scripts/ai_notebook_router_admission_readonly.rb"
VERSION_ONLY = ROOT / "scripts/ai_mihomo_version_only_readonly.rb"
NATIVE = ROOT / "scripts/ai_notebook_native_capability_test.rb"
PRIVATE_COPY = ROOT / "scripts/ai_real_config_private_copy_native_gate.rb"
PROVIDER_INVENTORY = ROOT / "scripts/ai_rule_provider_inventory_readonly.rb"
GEO_FLAGS_ONLY = ROOT / "scripts/ai_geo_flags_only_readonly.rb"
LIGHT = ROOT / "scripts/ai_notebooklm_cta_light_probe.rb"

# The TTYD LoadError happened after successfully loading psych.
DEVICE_CONFIRMED_RUBY_LIBRARIES = frozenset({"psych"})

DEVICE_CLI_ENTRYPOINTS = {ADMISSION, VERSION_ONLY, NATIVE, PRIVATE_COPY, PROVIDER_INVENTORY, GEO_FLAGS_ONLY}
DEVICE_BLOCKED_PENDING_DEPENDENCY_CHECK = {LIGHT}


def dependency_names(script: Path) -> set[str]:
    source = script.read_text(encoding="utf-8")
    return set(re.findall(r"""(?m)^\s*require\s+['"]([^'"]+)['"]""", source))


class TestIstoreOSRuntimeContract(unittest.TestCase):
    def test_user_executable_scripts_have_no_unverified_require(self):
        for path in DEVICE_CLI_ENTRYPOINTS:
            self.assertTrue(path.exists())
            self.assertTrue(
                dependency_names(path) <= DEVICE_CONFIRMED_RUBY_LIBRARIES,
                (path.name, sorted(dependency_names(path) -
                                   DEVICE_CONFIRMED_RUBY_LIBRARIES))
            )
            source = path.read_text(encoding="utf-8")
            self.assertNotRegex(source, r"""(?m)^\s*require_relative\b""")
            self.assertNotRegex(source, r"\bTimeout\s*\.")
            self.assertNotRegex(source, r"""(?m)^\s*require\s+['"]timeout['"]""")
            if path == GEO_FLAGS_ONLY:
                self.assertIn("RULE_PROVIDER_CACHES=NOT_READ", source)
                self.assertIn("PRIVATE_COPY_TEST=NOT_RUN", source)
                self.assertIn("PRODUCTION_CONFIG=UNCHANGED", source)
                self.assertNotIn("Process.spawn(", source)
            if path == PROVIDER_INVENTORY:
                self.assertIn("PRIVATE_COPY_TEST=NOT_RUN", source)
                self.assertIn("RULE_CONTENT=NOT_READ", source)
                self.assertIn("PRODUCTION_CONFIG=UNCHANGED", source)
                self.assertNotIn("Process.spawn(", source)
            if path == PRIVATE_COPY:
                self.assertIn("Process.spawn", source)
                self.assertIn("Process.waitpid2", source)
                self.assertIn("PRODUCTION_CONFIG=UNCHANGED", source)
                self.assertIn("SOURCE_CREDENTIALS=LOCAL_ONLY", source)
            if path == NATIVE:
                self.assertIn("Process.spawn", source)
                self.assertIn("Process.waitpid2", source)
                self.assertIn("PRODUCTION_CONFIG=UNCHANGED", source)
                self.assertNotIn("require 'psych'", source)
                self.assertIn("LISTENER_INSTALLED=NO", source)
            elif path not in (PRIVATE_COPY, PROVIDER_INVENTORY, GEO_FLAGS_ONLY):
                self.assertIn("IO.select", source)
                self.assertIn("read_nonblock", source)
                self.assertIn("PRODUCTION_WRITES=NONE", source)
            if path == VERSION_ONLY:
                self.assertNotIn("require 'psych'", source)
                self.assertIn("2>&1", source)
                self.assertIn("AUTO_SWITCH=OFF", source)

    def test_unverified_probe_is_not_marked_device_ready(self):
        self.assertTrue(DEVICE_BLOCKED_PENDING_DEPENDENCY_CHECK.isdisjoint(
            DEVICE_CLI_ENTRYPOINTS))
        self.assertIn(LIGHT, DEVICE_BLOCKED_PENDING_DEPENDENCY_CHECK)
        self.assertTrue(
            {"open3", "tempfile", "uri"}.issubset(dependency_names(LIGHT))
        )

    def test_runtime_gate_is_wired_into_existing_ci(self):
        workflow = (ROOT / ".github/workflows/check-egress-candidate.yml").read_text()
        self.assertIn("test_istoreos_runtime_contract.py", workflow)
        self.assertIn("ai_notebook_router_admission_readonly.rb", workflow)
        self.assertIn("ai_notebook_native_capability_test.rb", workflow)
        self.assertIn("ai_real_config_private_copy_native_gate.rb", workflow)
        self.assertIn("ai_rule_provider_inventory_readonly.rb", workflow)
        self.assertIn("ai_geo_flags_only_readonly.rb", workflow)


if __name__ == "__main__":
    unittest.main()
