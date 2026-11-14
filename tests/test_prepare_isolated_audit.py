import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout, redirect_stderr

import yaml

MODULE = Path(__file__).resolve().parents[1] / "scripts" / "prepare_isolated_audit.py"
spec = importlib.util.spec_from_file_location("prepare_isolated_audit", MODULE)
isolated = importlib.util.module_from_spec(spec)
spec.loader.exec_module(isolated)


def example_nodes():
    return {
        "proxies": [
            {"name": "台湾01", "type": "ss", "server": "node01.example.invalid",
             "port": 8443, "cipher": "aes-128-gcm", "password": "test-secret-only"},
            {"name": "台湾(02)", "type": "trojan", "server": "node02.example.invalid",
             "port": 443, "password": "second-test-secret"},
            {"name": "香港03", "type": "ss", "server": "hk.example.invalid",
             "port": 443, "password": "ignored"},
        ]
    }


class IsolatedAuditTests(unittest.TestCase):
    def test_exclusive_proxy_listeners_with_fail_closed_routing(self):
        config, inventory = isolated.build_isolated(
            example_nodes(), ["台湾01", "台湾(02)"], 17801
        )
        self.assertEqual([p["name"] for p in config["proxies"]], ["台湾01", "台湾(02)"])
        self.assertEqual([x["proxy"] for x in config["listeners"]], ["台湾01", "台湾(02)"])
        self.assertEqual([x["port"] for x in config["listeners"]], [17801, 17802])
        self.assertTrue(all(x["listen"] == "127.0.0.1" and x["type"] == "http"
                            for x in config["listeners"]))
        self.assertEqual(config["rules"], ["MATCH,REJECT"])
        self.assertFalse(config["allow-lan"])
        for key in ("tun", "external-controller", "mixed-port", "redir-port", "socks-port"):
            self.assertNotIn(key, config)
        self.assertEqual(inventory["schema_version"], 1)
        self.assertEqual(inventory["nodes"], [
            {"name": "台湾01", "proxy_url": "http://127.0.0.1:17801"},
            {"name": "台湾(02)", "proxy_url": "http://127.0.0.1:17802"},
        ])

    def test_selected_node_validation(self):
        for val in ([], ["台湾01", "台湾01"], ["DIRECT"], ["REJECT"],
                    ["x\ny"], list(range(33)), "台湾01"):
            with self.subTest(value=str(val)[:50]), self.assertRaises(ValueError):
                isolated.validate_selected(val)

    def test_absent_or_duplicate_provider_nodes_rejected(self):
        with self.assertRaises(ValueError):
            isolated.build_isolated(example_nodes(), ["台湾99"], 17801)
        duplicates = example_nodes()
        duplicates["proxies"].append(duplicates["proxies"][0])
        with self.assertRaises(ValueError):
            isolated.build_isolated(duplicates, ["台湾01"], 17801)
        with self.assertRaises(ValueError):
            isolated.build_isolated({"proxies": [{"name": "DIRECT", "type": "direct"}]},
                                    ["DIRECT"], 17801)

    def test_invalid_port_range_rejected(self):
        with self.assertRaises(ValueError):
            isolated.build_isolated(example_nodes(), ["台湾01", "台湾(02)"], 65535)
        with self.assertRaises(ValueError):
            isolated.build_isolated(example_nodes(), ["台湾01"], 7890)

    def test_private_file_permissions_no_secrets_in_stdout_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "airports.private.yaml"
            names = root / "selected.private.json"
            dest = root / "isolated"
            source.write_text(yaml.safe_dump(example_nodes(), allow_unicode=True),
                              encoding="utf-8")
            names.write_text(json.dumps(["台湾01", "台湾(02)"], ensure_ascii=False),
                             encoding="utf-8")
            args = ["isolated", "--node-config", str(source), "--names-json",
                    str(names), "--output-dir", str(dest), "--start-port", "17811"]
            stdout = io.StringIO()
            with patch("sys.argv", args), patch.object(isolated, "reserve_check"):
                with redirect_stdout(stdout):
                    self.assertEqual(isolated.main(), 0)
            self.assertNotIn("test-secret", stdout.getvalue())
            self.assertTrue((dest / "isolated-mihomo.yaml").is_file())
            self.assertTrue((dest / "egress-inventory.json").is_file())
            self.assertEqual(dest.stat().st_mode & 0o777, 0o700)
            for child in dest.iterdir():
                self.assertEqual(child.stat().st_mode & 0o777, 0o600)
            private_cfg = yaml.safe_load((dest / "isolated-mihomo.yaml").read_text())
            self.assertIn("test-secret-only", str(private_cfg))
            self.assertNotIn("ignored", str(private_cfg))
            with patch("sys.argv", args), patch.object(isolated, "reserve_check"):
                with redirect_stderr(io.StringIO()):
                    self.assertEqual(isolated.main(), 2)

    def test_public_repo_output_and_input_rejected(self):
        self.assertRaises(ValueError, isolated.private_path, isolated.ROOT / "private.yaml")
        self.assertRaises(ValueError, isolated.private_path,
                          isolated.ROOT / "private" / "config.yaml")


if __name__ == "__main__":
    unittest.main()
