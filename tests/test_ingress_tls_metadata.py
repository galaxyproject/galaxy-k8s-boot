"""Exercise the role's TLS metadata tasks without a GCE VM or Kubernetes cluster."""
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / "roles/galaxy_k8s_deployment"
ANSIBLE_PLAYBOOK = shutil.which("ansible-playbook")


@unittest.skipUnless(ANSIBLE_PLAYBOOK, "ansible-playbook is not installed")
class IngressTlsMetadataTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.responses = {}
        self.requests = Counter()
        responses, requests = self.responses, self.requests

        class MetadataHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                attribute = self.path.rsplit("/", 1)[-1]
                attempt = requests[attribute]
                requests[attribute] += 1
                answers = responses.get(attribute, [(404, "")])
                status, content = answers[min(attempt, len(answers) - 1)]
                self.send_response(status)
                self.end_headers()
                self.wfile.write(content.encode())

            def log_message(self, *args):
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), MetadataHandler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f"http://127.0.0.1:{self.server.server_port}/{{{{ item }}}}"

    def run_metadata_tasks(self, *, on_gce=True, unavailable=False, **overrides):
        role_tasks = yaml.safe_load((ROLE / "tasks/ingress_setup.yml").read_text())
        first = next(i for i, t in enumerate(role_tasks) if t["name"] == "Read the TLS certificate from the instance metadata")
        last = next(i for i, t in enumerate(role_tasks) if t["name"] == "Configure the provided certificate as the ingress controller's default")
        tasks = copy.deepcopy(role_tasks[first:last])
        fetch = tasks[0]["block"][0]
        fetch["ansible.builtin.uri"]["url"] = self.url
        # Keep the role's retry conditions/count; remove only the delay for tests.
        fetch["delay"] = 0
        if unavailable:
            # Reserve a port without listening so the connection is refused.
            import socket

            sock = socket.socket()
            sock.bind(("127.0.0.1", 0))
            self.addCleanup(sock.close)
            fetch["ansible.builtin.uri"]["url"] = f"http://127.0.0.1:{sock.getsockname()[1]}/{{{{ item }}}}"

        result_path = self.dir / "resolved.json"
        tasks.append({
            "ansible.builtin.copy": {
                "dest": str(result_path),
                "content": "{{ {'cert': _ingress_tls_cert, 'key': _ingress_tls_key, 'client_ca': _ingress_tls_client_ca} | to_json }}",
                "mode": "0600",
            },
            "no_log": True,
        })
        variables = yaml.safe_load((ROLE / "defaults/main.yml").read_text())
        variables["ansible_facts"] = {"product_name": "Google Compute Engine" if on_gce else "Other"}
        variables.update(overrides)
        play = [{"hosts": "localhost", "gather_facts": False, "vars": variables, "tasks": tasks}]
        playbook = self.dir / "metadata.yml"
        playbook.write_text(yaml.safe_dump(play, sort_keys=False))
        env = os.environ.copy()
        env.update({
            "ANSIBLE_LOCAL_TEMP": str(self.dir / "ansible-local"),
            "ANSIBLE_REMOTE_TEMP": str(self.dir / "ansible-remote"),
            "ANSIBLE_STDOUT_CALLBACK": "default",
            "NO_PROXY": "127.0.0.1,localhost",
            "no_proxy": "127.0.0.1,localhost",
        })
        result = subprocess.run(
            [ANSIBLE_PLAYBOOK, "-i", "localhost,", "-c", "local", "-e", f"ansible_python_interpreter={sys.executable}", str(playbook)],
            # Three attributes, three attempts each, 5 s per attempt when the
            # connection hangs rather than being refused (macOS): allow for it.
            env=env, text=True, capture_output=True, timeout=120,
        )
        resolved = json.loads(result_path.read_text()) if result_path.exists() else None
        return result, resolved

    def test_missing_attributes_keep_the_default_certificate_without_retries(self):
        result, resolved = self.run_metadata_tasks()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(resolved, {"cert": "", "key": "", "client_ca": ""})
        self.assertEqual(self.requests, {"galaxy_tls_cert": 1, "galaxy_tls_key": 1, "galaxy_tls_client_ca": 1})

    def test_transient_errors_are_retried_and_the_material_is_used(self):
        self.responses.update({
            "galaxy_tls_cert": [(503, "try again"), (200, "test certificate")],
            "galaxy_tls_key": [(429, "try again"), (200, "test private key")],
            "galaxy_tls_client_ca": [(500, "try again"), (200, "test client ca")],
        })
        result, resolved = self.run_metadata_tasks()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(resolved, {"cert": "test certificate", "key": "test private key", "client_ca": "test client ca"})
        self.assertEqual(self.requests, {"galaxy_tls_cert": 2, "galaxy_tls_key": 2, "galaxy_tls_client_ca": 2})

    def test_server_pair_without_client_ca_fails_on_gce(self):
        self.responses.update({
            "galaxy_tls_cert": [(200, "test certificate")],
            "galaxy_tls_key": [(200, "test private key")],
        })
        result, resolved = self.run_metadata_tasks()
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(resolved)
        self.assertIn("galaxy_tls_client_ca was not", result.stdout)

    def test_server_pair_without_client_ca_is_allowed_outside_gce(self):
        self.responses.update({
            "galaxy_tls_cert": [(200, "test certificate")],
            "galaxy_tls_key": [(200, "test private key")],
        })
        result, resolved = self.run_metadata_tasks(on_gce=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(resolved, {"cert": "test certificate", "key": "test private key", "client_ca": ""})

    def test_client_ca_without_server_pair_fails_everywhere(self):
        self.responses.update({"galaxy_tls_client_ca": [(200, "test client ca")]})
        for on_gce in (True, False):
            with self.subTest(on_gce=on_gce):
                result, resolved = self.run_metadata_tasks(on_gce=on_gce)
                self.assertNotEqual(result.returncode, 0)
                self.assertIsNone(resolved)
                self.assertIn("without galaxy_tls_cert and galaxy_tls_key", result.stdout)

    def test_persistent_errors_fail_instead_of_using_the_default_certificate(self):
        self.responses.update({name: [(503, "try again")] for name in ("galaxy_tls_cert", "galaxy_tls_key")})
        result, resolved = self.run_metadata_tasks()
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(resolved)
        self.assertIn("TLS metadata could not be read after retries", result.stdout)
        self.assertGreater(self.requests["galaxy_tls_cert"], 1)

    def test_unavailable_metadata_on_gce_fails_after_retries(self):
        result, resolved = self.run_metadata_tasks(unavailable=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(resolved)
        self.assertIn("TLS metadata could not be read after retries", result.stdout)

    def test_unavailable_metadata_outside_gce_remains_optional(self):
        result, resolved = self.run_metadata_tasks(on_gce=False, unavailable=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(resolved, {"cert": "", "key": "", "client_ca": ""})

    def test_metadata_can_be_disabled_on_gce(self):
        result, resolved = self.run_metadata_tasks(ingress_tls_from_metadata=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(resolved, {"cert": "", "key": "", "client_ca": ""})
        self.assertFalse(self.requests)

    def test_explicit_material_skips_metadata(self):
        result, resolved = self.run_metadata_tasks(
            galaxy_tls_cert="explicit certificate", galaxy_tls_key="explicit key", galaxy_tls_client_ca="explicit ca"
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(resolved, {"cert": "explicit certificate", "key": "explicit key", "client_ca": "explicit ca"})
        self.assertFalse(self.requests)


if __name__ == "__main__":
    unittest.main()
