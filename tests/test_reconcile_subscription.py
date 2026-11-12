"""Dynamic airport refresh: count can vary, credentials/route may change under same name."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import yaml

ROOT=Path(__file__).resolve().parents[1]
P=ROOT/"scripts"/"reconcile_subscription.py"
spec=importlib.util.spec_from_file_location("reconcile_subscription_test",P)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
reconcile=mod


def cfg(names):
    return {"proxies":[{"name":name,"type":"ss","server":f"host{i}.example.invalid",
                         "port":443,"cipher":"aes-128-gcm","password":f"secret{i}"}
                        for i,name in enumerate(names)]}


def snapshot(data):
    return {"sha256":"a"*64,"byte_count":99}


def manifest(data):
    return reconcile.build_manifest(data,snapshot(data))


class SubscriptionReconciliationTests(unittest.TestCase):
    def test_add_remove_rename_same_name_new_route_counts_not_fixed(self):
        initial=cfg(["香港01","日本02","美国03"])
        old=manifest(initial)
        same=manifest(cfg(["香港01","日本02","美国03"]))
        self.assertEqual(reconcile.compare_manifests(old,same)["unchanged"],3)
        self.assertFalse(reconcile.compare_manifests(old,same)["audit_required"])
        grown=manifest(cfg(["香港01","日本02","美国03","未知04"]))
        diff=reconcile.compare_manifests(old,grown)
        self.assertEqual(diff["current"],4)
        self.assertEqual((diff["added"],diff["removed"],diff["replaced_same_name"]),(1,0,0))
        self.assertTrue(diff["audit_required"])
        smaller=manifest(cfg(["香港01","美国03"]))
        diff=reconcile.compare_manifests(old,smaller)
        self.assertEqual(diff["current"],2)
        self.assertEqual(diff["removed"],1)
        renamed=cfg(["香港新版","日本02","美国03"])
        diff=reconcile.compare_manifests(old,manifest(renamed))
        self.assertEqual((diff["added"],diff["removed"]),(1,1))

    def test_same_label_endpoint_or_password_change_invalidates_old_verdict(self):
        old=manifest(cfg(["香港01","日本02"]))
        changed=cfg(["香港01","日本02"])
        changed["proxies"][0]["server"]="new-exit.example.invalid"
        diff=reconcile.compare_manifests(old,manifest(changed))
        self.assertEqual(diff["replaced_same_name"],1)
        self.assertEqual(diff["unchanged"],1)
        changed=cfg(["香港01","日本02"])
        changed["proxies"][0]["password"]="rotated-credential"
        self.assertEqual(reconcile.compare_manifests(old,manifest(changed))["replaced_same_name"],1)

    def test_arbitrary_node_count_and_unknown_labels(self):
        old=manifest(cfg(["IPLC", "没有国家", "香港01"]))
        big=manifest(cfg([f"自定义_{i:03d}" for i in range(233)]))
        diff=reconcile.compare_manifests(old,big)
        self.assertEqual(diff["current"],233)
        self.assertEqual(diff["added"],233)
        self.assertEqual(diff["removed"],3)
        self.assertTrue(diff["audit_required"])

    def test_cli_writes_private_manifest_and_no_credentials_in_stdout(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp); f=home/"source.private.yaml"; output1=home/"snapshot1.json"
            f.write_text(yaml.safe_dump(cfg(["香港01","日本02"]),allow_unicode=True),encoding="utf-8")
            args=["reconcile_subscription.py","--node-config",str(f),"--manifest-output",str(output1)]
            stdout=io.StringIO()
            with patch("sys.argv",args),contextlib.redirect_stdout(stdout):
                self.assertEqual(reconcile.main(),0)
            self.assertEqual(output1.stat().st_mode & 0o777,0o600)
            text=stdout.getvalue()
            for bad in ["香港01","日本02","secret0","host0","sha256"]:
                self.assertNotIn(bad,text)
            saved=json.loads(output1.read_text(encoding="utf-8"))
            self.assertEqual(saved["node_count"],2)
            f.write_text(yaml.safe_dump(cfg(["香港01","日本02","美国03"]),allow_unicode=True),encoding="utf-8")
            output2=home/"snapshot2.json"
            args=["reconcile_subscription.py","--node-config",str(f),
                  "--previous-manifest",str(output1),"--manifest-output",str(output2)]
            stdout=io.StringIO()
            with patch("sys.argv",args),contextlib.redirect_stdout(stdout):
                self.assertEqual(reconcile.main(),0)
            self.assertIn('"added": 1',stdout.getvalue())
            self.assertIn('"current": 3',stdout.getvalue())
            with patch("sys.argv",args),contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(reconcile.main(),2) # must not overwrite existing private output

    def test_missing_or_corrupt_history_rejected(self):
        current=manifest(cfg(["香港01"]))
        for previous in ({"schema_version":2}, {"schema_version":1},
                         current|{"node_count":0}):
            with self.assertRaises(ValueError):
                reconcile.compare_manifests(previous,current)

if __name__=="__main__":
    unittest.main()
