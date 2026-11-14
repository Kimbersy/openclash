"""Read-only all-region census on variable-count active YAML (no secrets leaked)."""
import shutil
import subprocess
from pathlib import Path
import tempfile
import unittest
import yaml

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/"scripts"/"inspect_active_subscription.rb"

@unittest.skipUnless(shutil.which("ruby"),"Ruby required for iStoreOS helper integration test")
class RubyCensusTests(unittest.TestCase):
    def run_census(self,names):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"private.yaml"
            nodes=[{"name":n,"type":"ss","server":"hidden-node.example.invalid",
                    "port":443,"password":"must-never-print"} for n in names]
            path.write_text(yaml.safe_dump({"proxies":nodes},allow_unicode=True),encoding="utf-8")
            return subprocess.run(["ruby",str(SCRIPT),str(path)],
                                  text=True,capture_output=True,timeout=10)

    def test_all_region_unknown_and_ambiguous_counts_only(self):
        result=self.run_census([
            "香港01", "台湾02", "日本03", "香港/Taiwan", "IPLC 专线", "Canada 04",
            "韩国05", "德国06", "🇺🇸US07"
        ])
        self.assertEqual(result.returncode,0,result.stderr)
        for value in ("hidden-node","must-never-print","香港01","台湾02","IPLC 专线"):
            self.assertNotIn(value,result.stdout)
        self.assertIn("CURRENT_NODE_COUNT=9",result.stdout)
        for label in ("AMBIGUOUS:1","HK:1","TW:1","JP:1","CA:1","KR:1","DE:1","US:1","UNKNOWN:1"):
            self.assertIn(label,result.stdout)

    def test_subscription_count_fluctuates_across_refreshes(self):
        a=self.run_census(["香港01"]*0 + ["香港01", "未标注"])
        b=self.run_census(["香港01","未标注","新加坡03","澳洲04","法国05"])
        self.assertEqual(a.returncode,0,a.stderr)
        self.assertEqual(b.returncode,0,b.stderr)
        self.assertIn("CURRENT_NODE_COUNT=2",a.stdout)
        self.assertIn("CURRENT_NODE_COUNT=5",b.stdout)
        self.assertIn("UNKNOWN:1",a.stdout)
        self.assertIn("UNKNOWN:1",b.stdout)

    def test_corrupt_source_only_reports_generic_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"secret.yaml"
            path.write_text("proxies: [private: secret\n",encoding="utf-8")
            result=subprocess.run(["ruby",str(SCRIPT),str(path)],
                                  text=True,capture_output=True,timeout=10)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(result.stdout,"")
            self.assertIn("PRIVATE_CONFIG_CENSUS_FAILED",result.stderr)
            self.assertNotIn("secret.yaml",result.stderr)

if __name__=="__main__":
    unittest.main()
