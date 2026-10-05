"""Pin the invariants the mTLS annotations on the Galaxy Ingress depend on.

ingress-nginx (allow-cross-namespace-resources off, its default) rejects an
auth-tls-secret reference to another namespace, and the rejection is a 403 for
the whole server rather than an ignored annotation. The CA Secret and the
Ingress that references it therefore have to share a namespace, and the
annotation values have to be ones the controller accepts.
"""
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / "roles/galaxy_k8s_deployment/tasks/galaxy_application.yml"
PREFIX = "nginx.ingress.kubernetes.io/"


def find_task(tasks, name):
    return next(t for t in tasks if t.get("name") == name)


class IngressClientAuthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tasks = yaml.safe_load(TASKS.read_text())
        cls.secret = find_task(cls.tasks, "Store the client CA the Galaxy Ingress verifies clients against")
        cls.helm = find_task(cls.tasks, "Helm install Galaxy")
        cls.annotations = cls.helm["vars"]["_helm_values_client_auth"]["ingress"]["annotations"]

    def test_secret_is_created_in_the_ingress_namespace(self):
        metadata = self.secret["kubernetes.core.k8s"]["definition"]["metadata"]
        self.assertEqual(metadata["namespace"], self.helm["kubernetes.core.helm"]["namespace"])
        self.assertEqual(metadata["name"], "{{ ingress_tls_client_ca_secret }}")
        self.assertIn("ca.crt", self.secret["kubernetes.core.k8s"]["definition"]["data"])

    def test_annotation_references_the_secret_in_the_same_namespace(self):
        namespace, name = self.annotations[PREFIX + "auth-tls-secret"].split("/")
        self.assertEqual(namespace, self.helm["kubernetes.core.helm"]["namespace"])
        self.assertEqual(name, "{{ ingress_tls_client_ca_secret }}")

    def test_verification_is_required_not_optional(self):
        self.assertEqual(self.annotations[PREFIX + "auth-tls-verify-client"], "on")
        self.assertIn("auth-tls-verify-depth", {k.removeprefix(PREFIX) for k in self.annotations})

    def test_secret_task_runs_only_with_a_validated_ca_and_hides_it(self):
        self.assertIn("_ingress_tls_client_ca_pem", self.secret["when"])
        self.assertTrue(self.secret["no_log"])

    def test_client_auth_values_are_applied_only_with_a_ca(self):
        values = self.helm["kubernetes.core.helm"]["values"]
        self.assertIn("_helm_values_client_auth if (_ingress_tls_client_ca | default('') | length > 0)", values)


if __name__ == "__main__":
    unittest.main()
