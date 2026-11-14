"""One-shot netns capability probe is no-op on parent network and fail-closed."""
from pathlib import Path
import re
import subprocess
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/ai_netns_capability_readonly.sh"

class NetnsCapabilityTests(unittest.TestCase):
    def test_shell_syntax_and_anonymous_smoke(self):
        subprocess.run(["sh", "-n", str(SCRIPT)], check=True)
        out = subprocess.run(["sh", str(SCRIPT)], check=True, text=True,
                             capture_output=True, timeout=10).stdout
        self.assertIn("NETNS_CAPABILITY_PROBE=START", out)
        self.assertRegex(out, r"NETNS_RESULT=(CHILD_NAMESPACE_DISTINCT|HOLD_[A-Z_]+)")
        self.assertIn("NETWORK_EGRESS_DENIAL=NOT_PROVEN", out)
        self.assertIn("PRIVATE_CONFIG_TEST=NOT_RUN", out)
        self.assertIn("AUTO_SWITCH=OFF", out)

    def test_no_network_or_router_side_effect_commands(self):
        src = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("unshare -n sh -c", src)
        self.assertIn("NETWORK_EGRESS_DENIAL=NOT_PROVEN", src)
        self.assertNotRegex(src, r"(?m)^\s*(?:curl|wget|iptables|nft|ip|route|mihomo|clash|kill|rm|cp|mv|sed)\s")
        self.assertNotIn("config.yaml", src)
        self.assertNotIn("rule-providers", src)
        self.assertNotIn("openclash.sh", src)

if __name__ == "__main__":
    unittest.main()
