"""No stale region/service candidate after a dynamic airport subscription refresh."""
import contextlib
from datetime import datetime, timezone
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import subscription_snapshot as snap

def load(name):
    loc=ROOT / "scripts" / (name + ".py")
    spec=importlib.util.spec_from_file_location(name+"_dynamic",loc)
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

prepare=load("prepare_isolated_audit")
egress=load("audit_egress")
render=load("render_verified_candidate")


def example_config():
    return {"proxies": [
        {"name": "香港01", "type": "ss", "server": "host1.example.invalid",
         "port": 443, "cipher": "aes-128-gcm", "password": "private-test-secret"},
        {"name": "日本02", "type": "ss", "server": "host2.example.invalid",
         "port": 443, "cipher": "aes-128-gcm", "password": "private-test-secret2"},
    ]}


def write_yaml(path, config):
    path.write_text(yaml.safe_dump(config, sort_keys=True, allow_unicode=True), encoding="utf-8")


class DynamicSubscriptionTests(unittest.TestCase):
    def test_unchanged_source_is_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"private.yaml"
            write_yaml(path,example_config())
            a=snap.read_private_snapshot(path)
            self.assertEqual(a["byte_count"],path.stat().st_size)
            snap.assert_current_snapshot(a,path)

    def test_node_add_remove_rename_or_same_label_route_change_invalidates(self):
        original=example_config()
        variants={}
        more=example_config(); more["proxies"].append({
            "name": "美国03", "type": "ss", "server": "host3.example.invalid",
            "port": 443, "cipher": "aes-128-gcm", "password": "new"})
        variants["add"]=more
        fewer=example_config(); fewer["proxies"].pop()
        variants["remove"]=fewer
        renamed=example_config(); renamed["proxies"][0]["name"]="香港已更名"
        variants["rename"]=renamed
        migrated=example_config(); migrated["proxies"][0]["server"]="migrated.example.invalid"
        variants["same_label_changed_server"]=migrated
        new_pass=example_config(); new_pass["proxies"][0]["password"]="new-password"
        variants["same_label_changed_auth"]=new_pass
        reorder=example_config(); reorder["proxies"].reverse()
        variants["reordered"]=reorder
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"private.yaml"
            write_yaml(path,original)
            fingerprint=snap.read_private_snapshot(path)
            for kind,value in variants.items():
                with self.subTest(change=kind):
                    write_yaml(path,value)
                    with self.assertRaisesRegex(ValueError,"subscription changed"):
                        snap.assert_current_snapshot(fingerprint,path)

    def test_missing_corrupt_or_malformed_snapshot_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"private.yaml"
            write_yaml(path,example_config())
            for sample in (None,{}, {"sha256": "a"*64},
                           {"sha256":"x"*64, "byte_count":40},
                           {"sha256":"a"*64, "byte_count":True},
                           {"sha256":"a"*64, "byte_count":40, "debug":"secret"}):
                with self.subTest(metadata=sample),self.assertRaises(ValueError):
                    snap.assert_current_snapshot(sample,path)

    def test_prepared_inventory_binds_entire_current_subscription_not_only_selected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"airport.yaml"
            write_yaml(path,example_config())
            selected=["香港01"]
            isolated,inventory=prepare.build_isolated(example_config(),selected,17801)
            inventory["subscription_snapshot"]=snap.read_private_snapshot(path)
            inventory["source_node_count"]=len(example_config()["proxies"])
            self.assertEqual(len(inventory["nodes"]),1)
            self.assertEqual(inventory["source_node_count"],2)
            with patch.object(egress,"probe",return_value=([
                {"source":"ipinfo","ip":"203.0.113.8","country":"HK"},
                {"source":"ipapi","ip":"203.0.113.8","country":"HK"},
            ],[])):
                result=egress.audit(inventory)
            self.assertEqual(result["subscription_snapshot"],inventory["subscription_snapshot"])
            self.assertEqual(result["source_node_count"],2)

    def test_audit_cli_rejects_changed_subscription_without_probing_or_writing_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); config=root/"private.yaml"; inv=root/"private.json"; report=root/"report.json"
            write_yaml(config,example_config())
            inventory={
                "schema_version":1,
                "nodes":[{"name":"香港01","proxy_url":"http://127.0.0.1:17801"}],
                "source_node_count":2,
                "subscription_snapshot":snap.read_private_snapshot(config)
            }
            inv.write_text(json.dumps(inventory),encoding="utf-8")
            variant=example_config()
            variant["proxies"][0]["server"]="replaced.example.invalid"
            write_yaml(config,variant)
            args=["audit_egress.py","--inventory",str(inv),"--node-config",str(config),"--report",str(report)]
            with patch("sys.argv",args),patch.object(egress,"probe") as probe,contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(egress.main(),2)
            probe.assert_not_called()
            self.assertFalse(report.exists())

    def test_candidate_cli_rejects_changed_subscription_even_with_fresh_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); config=root/"private.yaml"; report=root/"report.json"; out=root/"new_candidate"
            write_yaml(config,example_config())
            now=datetime.now(timezone.utc).isoformat()
            data={
                "schema_version":1, "generated_at":now,
                "subscription_snapshot":snap.read_private_snapshot(config),
                "source_node_count":2,
                "nodes":[{"name":"香港01","status":"match","claimed_country":"HK",
                          "observed_country":"HK","egress_verified":True,
                          "evidence_sources":["ipinfo","ipapi"],
                          "observed_ips":["203.0.113.8"],"service_availability":{}}],
            }
            report.write_text(json.dumps(data),encoding="utf-8")
            variant=example_config(); variant["proxies"].pop()
            write_yaml(config,variant)
            args=["render_verified_candidate.py","--report",str(report),
                  "--node-config",str(config),"--output-dir",str(out)]
            with patch("sys.argv",args),contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(render.main(),2)
            self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main()
