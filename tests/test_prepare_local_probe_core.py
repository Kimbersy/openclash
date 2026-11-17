"""Minimal iStoreOS Ruby/Psych fallback, with no optional Ruby stdlib packages."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import yaml

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/"scripts"/"prepare_local_probe_core.rb"

@unittest.skipUnless(shutil.which("ruby"),"ruby unavailable")
class MinimalOpenWrtRubyTests(unittest.TestCase):
    def call(self, nodes):
        temp=tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root=Path(temp.name)
        source=root/"private-airport.yaml"
        source.write_text(yaml.safe_dump({"proxies":nodes},allow_unicode=True),encoding="utf-8")
        run=subprocess.run(["ruby",str(SCRIPT),str(source),str(root)],
                           env={**os.environ,"OC_TEST_MODE":"1","LANG":"C"},
                           text=True,capture_output=True,timeout=10)
        return run,root

    @staticmethod
    def node(name, server="example.invalid"):
        return {"name":name,"type":"ss","server":server,
                "port":443,"cipher":"aes-128-gcm","password":"PRIVATE_FAKE_CREDENTIAL"}

    def test_hk_outbound_only_on_loopback_no_optional_gems(self):
        result,root=self.call([self.node("日本02"),self.node("香港01"),self.node("IPLC03")])
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn("CURRENT_NODE_COUNT=3 HK_CANDIDATES=1",result.stdout)
        self.assertIn("STARTED=NO",result.stdout)
        self.assertNotIn("PRIVATE_FAKE_CREDENTIAL",result.stdout+result.stderr)
        self.assertNotIn("example.invalid",result.stdout+result.stderr)
        dirs=list(root.glob("openclash-probe-*"))
        self.assertEqual(len(dirs),1)
        private=dirs[0]/"isolated.yaml"
        self.assertTrue(private.is_file())
        self.assertEqual(dirs[0].stat().st_mode & 0o777,0o700)
        self.assertEqual(private.stat().st_mode & 0o777,0o600)
        generated=yaml.safe_load(private.read_text(encoding="utf-8"))
        self.assertEqual(len(generated["proxies"]),1)
        self.assertEqual(generated["proxies"][0]["name"],"香港01")
        self.assertEqual(generated["listeners"][0]["proxy"],"香港01")
        self.assertEqual(generated["listeners"][0]["listen"],"127.0.0.1")
        self.assertEqual(generated["listeners"][0]["port"],17881)
        self.assertFalse(generated["tun"]["enable"])
        self.assertFalse(generated["allow-lan"])
        self.assertEqual(generated["rules"],["MATCH,REJECT"])
        self.assertEqual(generated["external-controller"],"")
        self.assertEqual(generated["port"],0)

    def test_dynamic_node_count_and_no_hk_fails_closed(self):
        result,root=self.call([self.node("日本01")]*0+[self.node("日本01")])
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn("PRIVATE_PREP_FAILED",result.stderr)
        self.assertFalse(list(root.glob("openclash-probe-*")))
        self.assertNotIn("日本01",result.stdout+result.stderr)
        result,root=self.call([self.node("香港01")])
        self.assertIn("CURRENT_NODE_COUNT=1",result.stdout)
        result,root=self.call([self.node("香港01"),self.node("日本01"),self.node("澳洲01")])
        self.assertIn("CURRENT_NODE_COUNT=3",result.stdout)

    def test_duplicate_names_rejected(self):
        result,root=self.call([self.node("香港01"),self.node("香港01")])
        self.assertIn("PRIVATE_PREP_FAILED",result.stderr)
        self.assertFalse(list(root.glob("openclash-probe-*")))

    def test_module_dependencies_only_psych(self):
        text=SCRIPT.read_text(encoding="utf-8")
        self.assertEqual([line for line in text.splitlines() if line.startswith("require ")],["require 'psych'"])
        self.assertNotIn("Dir.mktmpdir",text)
        self.assertNotIn("FileUtils",text)
        self.assertNotIn("Digest",text)
        self.assertNotIn("JSON",text)

if __name__=="__main__":
    unittest.main()
