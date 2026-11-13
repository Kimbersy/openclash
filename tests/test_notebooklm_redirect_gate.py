"""Offline regression: NotebookLM region denial, login, app-entry and landing are distinct."""
import pathlib
import re
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "scripts/ai_network_batch_once.sh").read_text()
MATCH = re.search(r"<<'RUBY_NOTEBOOK'\n(.*?)\nRUBY_NOTEBOOK(?=\n|$)", SOURCE, re.S)
assert MATCH, "NotebookLM classifier must remain embedded in one-shot shell script"
CODE = MATCH.group(1)


def classify(rc, final, location=None, code="200", hops="1"):
    with tempfile.TemporaryDirectory() as d:
        header = pathlib.Path(d) / "headers"
        meta = pathlib.Path(d) / "metadata"
        lines = "HTTP/2 302\r\n"
        if location:
            lines += "location: " + location + "\r\n"
        lines += "\r\nHTTP/2 " + code + "\r\n\r\n"
        header.write_text(lines)
        meta.write_text(f"{code} 0.35 1.23 2000 {hops} {final}")
        r = subprocess.run(
            ["ruby", "-", str(header), str(meta), str(rc)],
            input=CODE, capture_output=True, text=True, check=True,
        )
        return r.stdout.strip()


class NotebookLmGateTest(unittest.TestCase):
    def test_location_unsupported_redirect_is_negative_even_if_final_200(self):
        url = "https://notebooklm.google/?location=unsupported"
        out = classify(0, url, location=url)
        self.assertEqual(out, "UNSUPPORTED_REDIRECT_OBSERVED 1")
        self.assertNotIn(url, out)

    def test_unsupported_in_intermediate_hop_is_not_lost(self):
        out = classify(0, "https://notebook.google/",
                       "https://notebooklm.google/?location=unsupported", hops="2")
        self.assertEqual(out, "UNSUPPORTED_REDIRECT_OBSERVED 2")

    def test_login_is_unknown(self):
        out = classify(0, "https://accounts.google.com/ServiceLogin?continue=private")
        self.assertEqual(out, "LOGIN_REQUIRED_UNKNOWN 1")
        self.assertNotIn("private", out)

    def test_app_entry_still_not_business_verified(self):
        out = classify(0, "https://notebook.google.com/notebook/e7e2e")
        self.assertEqual(out, "APP_ENTRY_CANDIDATE_NOT_VERIFIED 1")

    def test_marketing_page_not_app(self):
        self.assertEqual(classify(0, "https://notebook.google/"), "LANDING_ONLY_UNKNOWN 1")

    def test_http_200_with_curl28_is_incomplete(self):
        self.assertEqual(classify(28, "https://notebook.google.com/"),
                         "HTTP_INCOMPLETE_TIMEOUT 1")

    def test_plain_redirect_without_final_app_is_unknown(self):
        self.assertEqual(classify(0, "https://other.example/", code="301"),
                         "UNVERIFIED_REDIRECT_OR_HTTP 1")

    def test_access_denied_and_rate_limit_not_country_labels(self):
        self.assertEqual(classify(0, "https://notebook.google.com/", code="403"),
                         "ACCESS_DENIED_UNKNOWN_CAUSE 1")
        self.assertEqual(classify(0, "https://notebook.google.com/", code="429"),
                         "RATE_LIMITED 1")

    def test_missing_metadata_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            h = pathlib.Path(d) / "h"
            m = pathlib.Path(d) / "m"
            h.write_text("")
            m.write_text("")
            r = subprocess.run(["ruby", "-", str(h), str(m), "0"],
                               input=CODE, capture_output=True, text=True, check=True)
            self.assertEqual(r.stdout.strip(), "PARSER_FAILED 0")

    def test_exact_proxy_and_redirect_limits(self):
        self.assertIn("--proto-redir '=https'", SOURCE)
        self.assertIn("--max-redirs 5", SOURCE)
        self.assertIn("--proxy http://127.0.0.1:17881", SOURCE)
        self.assertNotIn("--cookie", SOURCE)
        self.assertIn("BUSINESS=UNKNOWN", SOURCE)


if __name__ == "__main__":
    unittest.main()
