"""Single-node Ruby probe must not change the live router or expose credentials."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "prepare_local_probe.rb"

@unittest.skipUnless(shutil.which("ruby"), "Ruby not available in CI")
class LocalProbeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source.yaml"

    def write(self, nodes):
        self.source.write_text(
            yaml.safe_dump({"proxies": nodes}, allow_unicode=True), encoding="utf-8"
        )

    def node(self, name, server="test.example.invalid"):
        return {"name": name, "type": "ss", "server": server, "port": 443,
                "cipher": "aes-128-gcm", "password": "FAKE_PRIVATE_PASSWORD"}

    def ruby(self, expression, *args):
        return subprocess.run(
            ["ruby", "-e", "require ARGV.shift; " + expression,
             str(SCRIPT), *map(str, args)],
            text=True, capture_output=True, timeout=10
        )

    def test_prepare_one_node_safely_with_exact_private_snapshot(self):
        self.write([self.node("香港01"), self.node("日本02"), self.node("IPLC03")])
        r = self.ruby(
            "prepare_one(ARGV[0], Integer(ARGV[1]), source_override:ARGV[2], output_root:ARGV[3])",
            "HK", 1, self.source, self.root)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("CURRENT_NODE_COUNT=3", r.stdout)
        self.assertIn("CANDIDATES=1 SAMPLE=1", r.stdout)
        self.assertIn("STARTED=NO LIVE_CONFIG_CHANGED=NO", r.stdout)
        for secret in ("FAKE_PRIVATE_PASSWORD", "香港01", "test.example.invalid"):
            self.assertNotIn(secret, r.stdout + r.stderr)
        line = next(x for x in r.stdout.splitlines() if x.startswith("PREPARED_PRIVATE_DIR="))
        out = Path(line.split("=",1)[1])
        self.assertEqual(out.stat().st_mode & 0o777,0o700)
        self.assertEqual({x.name for x in out.iterdir()}, {"isolated.yaml", "snapshot.json"})
        for file in out.iterdir():
            self.assertEqual(file.stat().st_mode & 0o777,0o600)
        cfg = yaml.safe_load((out / "isolated.yaml").read_text())
        self.assertEqual(len(cfg["proxies"]),1)
        self.assertEqual(cfg["proxies"][0]["name"],"香港01")
        self.assertEqual(cfg["proxies"][0]["password"],"FAKE_PRIVATE_PASSWORD")
        self.assertEqual(cfg["listeners"], [{
            "name":"private-egress-probe","type":"http",
            "listen":"127.0.0.1","port":17881,"proxy":"香港01"
        }])
        self.assertFalse(cfg["allow-lan"])
        self.assertFalse(cfg["tun"]["enable"])
        self.assertEqual(cfg["rules"], ["MATCH,REJECT"])
        self.assertEqual(cfg["port"],0)
        self.assertEqual(cfg["mixed-port"],0)
        self.assertEqual(cfg["external-controller"],"")
        manifest = json.loads((out / "snapshot.json").read_text())
        self.assertEqual(manifest["node_count"],3)
        good = self.ruby("verify_prepared(ARGV[0], source_override:ARGV[1])",out,self.source)
        self.assertEqual(good.returncode,0,good.stderr)
        self.assertIn("SNAPSHOT=CURRENT",good.stdout)
        self.write([self.node("香港01",server="changed.example.invalid"),self.node("日本02")])
        stale=self.ruby("verify_prepared(ARGV[0], source_override:ARGV[1])",out,self.source)
        self.assertNotEqual(stale.returncode,0)
        self.assertNotIn("changed.example.invalid",stale.stderr+stale.stdout)

    def test_dynamic_number_and_all_regions_including_unknown(self):
        self.write([self.node("IPLC01"), self.node("香港01"),self.node("美国02"),
                    self.node("台灣03"), self.node("日本04")])
        for region in ("UNKNOWN","HK","TW","JP","US"):
            with self.subTest(region=region):
                ret=self.ruby("prepare_one(ARGV[0], Integer(ARGV[1]), source_override:ARGV[2], output_root:ARGV[3])",
                              region, 1, self.source, self.root)
                self.assertEqual(ret.returncode,0,ret.stderr)
                self.assertIn("CURRENT_NODE_COUNT=5",ret.stdout)
        self.write([self.node("香港01")])
        ret=self.ruby("prepare_one(ARGV[0], 1, source_override:ARGV[1], output_root:ARGV[2])",
                      "HK", self.source, self.root)
        self.assertEqual(ret.returncode,0,ret.stderr)
        self.assertIn("CURRENT_NODE_COUNT=1",ret.stdout)

    def test_reject_missing_region_duplicate_and_dependent_proxy(self):
        self.write([self.node("香港01")])
        missing=self.ruby("prepare_one(ARGV[0], 1, source_override:ARGV[1], output_root:ARGV[2])",
                          "JP", self.source, self.root)
        self.assertNotEqual(missing.returncode,0)
        self.assertFalse(list(self.root.glob("openclash-probe-*")))
        self.write([self.node("香港01"),self.node("香港01")])
        dup=self.ruby("prepare_one(ARGV[0], 1, source_override:ARGV[1], output_root:ARGV[2])",
                      "HK", self.source, self.root)
        self.assertNotEqual(dup.returncode,0)
        other=self.node("香港01");other["dialer-proxy"]="nonlocal"
        self.write([other])
        dep=self.ruby("prepare_one(ARGV[0], 1, source_override:ARGV[1], output_root:ARGV[2])",
                      "HK", self.source, self.root)
        self.assertNotEqual(dep.returncode,0)

if __name__=="__main__":
    unittest.main()
