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
CACHE_BYTECOPY = ROOT / "scripts/ai_rule_cache_byte_copy_gate.rb"
CACHE_STRUCTURE = ROOT / "scripts/ai_rule_cache_structure_readonly.rb"
CACHE_SIZE_PROFILE = ROOT / "scripts/ai_rule_cache_size_profile_readonly.rb"
TWO_CACHE_STATIC = ROOT / "scripts/ai_two_cache_static_readonly.rb"
LIVE_RULE_PROVIDER = ROOT / "scripts/ai_live_rule_provider_readonly.rb"
RUNTIME_LEAF_INVENTORY = ROOT / "scripts/ai_runtime_leaf_inventory_readonly.rb"
SOURCE_RUNTIME_DEFS = ROOT / "scripts/ai_source_runtime_definitions_readonly.rb"
ACTIVE_SUBSCRIPTIONS = ROOT / "scripts/ai_active_subscriptions_metadata_readonly.rb"
PASSIVE_CANDIDATE = ROOT / "scripts/ai_refresh_passive_observer_candidate.rb"
PASSIVE_PREFLIGHT = ROOT / "scripts/ai_refresh_observer_runtime_preflight_readonly.rb"
UNATTENDED_SCHEDULE_PREFLIGHT = ROOT / "scripts/ai_unattended_schedule_capability_readonly.rb"
SOCKET_OWNER_DIAG = ROOT / "scripts/ai_controller_socket_diagnostic_readonly.rb"
LIGHT = ROOT / "scripts/ai_notebooklm_cta_light_probe.rb"

# The TTYD LoadError happened after successfully loading psych.
DEVICE_CONFIRMED_RUBY_LIBRARIES = frozenset({"psych"})

DEVICE_CLI_ENTRYPOINTS = {ADMISSION, VERSION_ONLY, NATIVE, PRIVATE_COPY, PROVIDER_INVENTORY, GEO_FLAGS_ONLY, CACHE_BYTECOPY, CACHE_STRUCTURE, CACHE_SIZE_PROFILE, TWO_CACHE_STATIC, LIVE_RULE_PROVIDER, SOCKET_OWNER_DIAG, RUNTIME_LEAF_INVENTORY, SOURCE_RUNTIME_DEFS, ACTIVE_SUBSCRIPTIONS, PASSIVE_PREFLIGHT, PASSIVE_CANDIDATE, UNATTENDED_SCHEDULE_PREFLIGHT}
# 2026-11-14 23:35 real-device PASS: NOFOLLOW, private flock, monotonic, signals.
# Only bounded foreground candidate (--probe / --observe) is admitted;
# cron/procd/background installation remains forbidden and never CI-proven.
DEVICE_BLOCKED_PENDING_DEPENDENCY_CHECK = {LIGHT}
# A previously admitted FOREGROUND observer does not mean fork/setsid is
# confirmed or operator approval to install a detached/background session.
DEVICE_UNATTENDED_BG_BLOCKED_PENDING_DEVICE_PROOF = {PASSIVE_CANDIDATE}


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
            if path == PASSIVE_CANDIDATE:
                for guard in ("HOLD_NOT_ARMED", "ARGV[0]=='--probe'",
                              "ARGV[0]=='--observe'", "MAX_SECONDS = 86_400",
                              "File::NOFOLLOW", "File::LOCK_EX|File::LOCK_NB",
                              "trap('TERM')", "trap('HUP')",
                              "TRUSTED_REMOTE_COMMIT=NOT_VERIFIED",
                              "ALLOW_RECONCILE=NO ALLOW_SWITCH=NO",
                              "PRODUCTION_CONFIG=UNCHANGED"):
                    self.assertIn(guard, source)
                self.assertNotIn("Process.spawn", source)
                self.assertNotIn("require_relative", source)
                self.assertNotIn("Net::HTTP", source)
            if path == UNATTENDED_SCHEDULE_PREFLIGHT:
                for guard in ("UNATTENDED_SCHEDULE_PREFLIGHT=START", "NO_HTTP=YES",
                              "DETACHED_SESSION=NOT_STARTED", "Process.respond_to?(:fork)",
                              "Process.respond_to?(:setsid)", "AUTO_SWITCH=OFF"):
                    self.assertIn(guard, source)
                self.assertNotIn("Process.fork(", source)
                self.assertNotIn("Process.setsid(", source)
                self.assertNotIn("File.open(", source)
            if path == PASSIVE_PREFLIGHT:
                for feature in ("File::NOFOLLOW", "File::LOCK_EX|File::LOCK_NB",
                                "Process::CLOCK_MONOTONIC", "UPDATER_CONTENT=NOT_READ",
                                "PASSIVE_OBSERVER_INSTALLED=NO"):
                    self.assertIn(feature, source)
                self.assertNotIn("IO.popen", source)
                self.assertNotIn("Process.spawn", source)
            if path == ACTIVE_SUBSCRIPTIONS:
                self.assertIn("UCI_READ_ONLY=YES", source)
                self.assertIn("ENABLED_SUBSCRIPTION_MERGE_PROVENANCE=NOT_VERIFIED", source)
                self.assertIn("SUBSCRIPTION_NAMES_URLS_AND_SECRETS=NOT_EMITTED", source)
                self.assertNotIn("Process.spawn", source)
            if path == SOURCE_RUNTIME_DEFS:
                self.assertIn("READ_ONLY_NO_HTTP=YES", source)
                self.assertIn("MIHOMO_MEMORY_CREDENTIALS=NOT_VERIFIED", source)
                self.assertIn("ENABLED_SUBSCRIPTION_MERGE_PROVENANCE=NOT_VERIFIED", source)
                self.assertNotIn("Process.spawn", source)
            if path == RUNTIME_LEAF_INVENTORY:
                self.assertIn("LIVE_FULL_CONNECTION_FINGERPRINTS=NOT_VERIFIED", source)
                self.assertIn("ENABLED_SUBSCRIPTION_SOURCE_COVERAGE=NOT_VERIFIED", source)
                self.assertIn("GET_ONLY_IPV4=YES", source)
                self.assertNotIn("Process.spawn", source)
            if path == SOCKET_OWNER_DIAG:
                self.assertIn("CONTROLLER_HTTP=NOT_REQUESTED", source)
                self.assertIn("PROVIDER_REFRESH=NOT_RUN", source)
                self.assertNotIn("IO.popen", source)
                self.assertNotIn("Process.spawn", source)
            if path == LIVE_RULE_PROVIDER:
                self.assertIn("PROVIDER_REFRESH=NOT_RUN", source)
                self.assertIn("GET_ONLY=YES", source)
                self.assertNotIn("require_relative", source)
                self.assertNotIn("Process.spawn", source)
            if path == TWO_CACHE_STATIC:
                self.assertIn("NETWORK_ISOLATION=NOT_PROVEN", source)
                self.assertIn("MRS_BINARY_CONTENT=NOT_PARSED", source)
                self.assertNotIn("Process.spawn", source)
            if path == CACHE_SIZE_PROFILE:
                self.assertIn("CACHE_CONTENT=NOT_READ", source)
                self.assertIn("NETWORK_ISOLATION=NOT_PROVEN", source)
                self.assertNotIn("Process.spawn", source)
            if path == CACHE_STRUCTURE:
                self.assertIn("NETWORK_ISOLATION=NOT_PROVEN", source)
                self.assertIn("MIHOMO_SYNTAX=NOT_VALIDATED", source)
                self.assertNotIn("Process.spawn", source)
            if path == CACHE_BYTECOPY:
                self.assertIn("PRIVATE_CONFIG_TEST=NOT_RUN", source)
                self.assertIn("AUTO_SWITCH=OFF", source)
                self.assertNotIn("Process.spawn", source)
                self.assertNotIn("require 'timeout'", source)
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
            elif path not in (PRIVATE_COPY, PROVIDER_INVENTORY, GEO_FLAGS_ONLY, CACHE_BYTECOPY, CACHE_STRUCTURE, CACHE_SIZE_PROFILE, TWO_CACHE_STATIC, LIVE_RULE_PROVIDER, SOCKET_OWNER_DIAG, RUNTIME_LEAF_INVENTORY, SOURCE_RUNTIME_DEFS, ACTIVE_SUBSCRIPTIONS, PASSIVE_PREFLIGHT, PASSIVE_CANDIDATE, UNATTENDED_SCHEDULE_PREFLIGHT):
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
        # Candidate requires target-confirmed File::NOFOLLOW, flock,
        # CLOCK_MONOTONIC and signal traps before any router-facing command.
        self.assertNotIn(PASSIVE_CANDIDATE, DEVICE_BLOCKED_PENDING_DEPENDENCY_CHECK)
        self.assertIn(PASSIVE_CANDIDATE, DEVICE_CLI_ENTRYPOINTS)
        source = PASSIVE_CANDIDATE.read_text(encoding="utf-8")
        self.assertEqual(set(), dependency_names(PASSIVE_CANDIDATE))
        for proof_gate in ("File::NOFOLLOW", "File::LOCK_EX|File::LOCK_NB",
                           "Process::CLOCK_MONOTONIC", "trap('TERM')",
                           "HOLD_NOT_ARMED", "TRUSTED_REMOTE_COMMIT=NOT_VERIFIED",
                           "ALLOW_RECONCILE=NO ALLOW_SWITCH=NO"):
            self.assertIn(proof_gate, source)
        self.assertNotIn("Process.spawn", source)

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
        self.assertIn("ai_rule_cache_byte_copy_gate.rb", workflow)
        self.assertIn("ai_rule_cache_structure_readonly.rb", workflow)
        self.assertIn("ai_rule_cache_size_profile_readonly.rb", workflow)
        self.assertIn("ai_two_cache_static_readonly.rb", workflow)
        self.assertIn("ai_live_rule_provider_readonly.rb", workflow)
        self.assertIn("ai_controller_socket_diagnostic_readonly.rb", workflow)
        self.assertIn("ai_runtime_leaf_inventory_readonly.rb", workflow)
        self.assertIn("ai_source_runtime_definitions_readonly.rb", workflow)
        self.assertIn("ai_active_subscriptions_metadata_readonly.rb", workflow)
        self.assertIn("ai_refresh_passive_observer_candidate.rb", workflow)
        self.assertIn("ai_refresh_observer_runtime_preflight_readonly.rb", workflow)
        self.assertIn("ai_unattended_schedule_capability_readonly.rb", workflow)
        self.assertIn(PASSIVE_CANDIDATE, DEVICE_UNATTENDED_BG_BLOCKED_PENDING_DEVICE_PROOF)


if __name__ == "__main__":
    unittest.main()
