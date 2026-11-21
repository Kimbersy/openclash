import os, pathlib, subprocess, tempfile, unittest

SCRIPT = pathlib.Path(__file__).parents[1] / 'scripts' / 'clash_home_input_change_gate_v1.sh'
VALID = """proxies:
  - name: "美国 A01 测试"
    type: anytls
    server: 203.0.113.1
    port: 443
    sni: example.org
  - name: "香港 A02 测试"
    type: vless
    server: 203.0.113.2
    port: 443
proxy-groups:
  - name: "AI"
    type: select
    proxies: ["美国 A01 测试"]
"""
BAD = VALID.replace('    sni: example.org\n', '')

class ChangeGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = pathlib.Path(self.tmp.name)
        self.root = root
        (root/'mockbin').mkdir()
        mock = root/'mockbin'/'docker'
        mock.write_text('#!/bin/sh\n[ "$1" = inspect ] || exit 3\nprintf "%s\\n" "$MOCK_IMAGE"\n')
        mock.chmod(0o755)
        self.source = root/'source.yaml'
        self.source.write_text('original version')
        self.cache = root/'cache'/'merged.yaml'
        self.cache.parent.mkdir()
        self.cache.write_text(VALID)
        self.env = dict(os.environ)
        self.env.update(
            CLASH_HOME_ROOT=str(root),
            CLASH_HOME_CHANGE_STATE=str(root/'cache'/'state'),
            CLASH_HOME_CACHE=str(self.cache),
            CLASH_HOME_MIN_AGE='0',
            CLASH_HOME_FAILURE_BACKOFF='3600',
            MOCK_IMAGE='sha256:original',
            PATH=str(root/'mockbin')+os.pathsep+self.env['PATH'],
        )

    def run_gate(self, mode, expected=0):
        r = subprocess.run(['sh',str(SCRIPT),mode,str(self.source)],env=self.env,capture_output=True,text=True,timeout=15)
        self.assertEqual(r.returncode, expected, r.stdout+'\n'+r.stderr)
        return r.stdout

    def test_change_success_then_unchanged(self):
        self.assertIn('CHANGED',self.run_gate('check'))
        self.assertIn('PASS',self.run_gate('ack'))
        self.assertIn('UNCHANGED',self.run_gate('check'))
        self.source.write_text('changed content')
        self.assertIn('CHANGED',self.run_gate('check'))

    def test_converter_image_change_trigger(self):
        self.run_gate('check'); self.run_gate('ack')
        self.env['MOCK_IMAGE']='sha256:newimage'
        self.assertIn('CHANGED',self.run_gate('check'))

    def test_failed_conversion_backoff(self):
        self.run_gate('check')
        self.assertIn('FAILED_NO_SUCCESS',self.run_gate('fail'))
        self.assertIn('BACKOFF',self.run_gate('check'))
        self.source.write_text('new subscriber upload')
        self.assertIn('CHANGED',self.run_gate('check'))

    def test_a01_sni_missing_cannot_ack(self):
        self.run_gate('check'); self.cache.write_text(BAD)
        self.assertIn('HOLD',self.run_gate('ack',expected=2))
        self.assertFalse((self.root/'cache/state/done.sha256').exists())

    def test_source_modified_during_refresh_cannot_ack(self):
        self.run_gate('check'); self.source.write_text('new mid-refresh data')
        self.assertIn('INPUT_CHANGED_WHILE_PROCESSING',self.run_gate('ack',expected=2))

    def test_recent_file_deferred(self):
        self.env['CLASH_HOME_MIN_AGE']='180'
        self.assertIn('DEFER',self.run_gate('check'))

    def test_missing_source_holds_without_path_leakage(self):
        self.source.unlink()
        out=self.run_gate('check',expected=2)
        self.assertIn('INVALID_INPUT_FILE',out)
        self.assertNotIn(str(self.source),out)

    def test_unexpected_converter_identity_holds(self):
        self.env['MOCK_IMAGE']='INVALID'
        self.assertIn('BAD_IMAGE_ID',self.run_gate('check',expected=2))

if __name__=='__main__':
    unittest.main(verbosity=2)
