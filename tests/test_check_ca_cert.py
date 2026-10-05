"""Run the CA certificate validation script the role applies to a Leo-injected client CA."""
import base64
import datetime
import ipaddress
import subprocess
import tempfile
import unittest
from pathlib import Path

try:
    # A dependency of ansible-core, so present wherever the playbook's tests run.
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID
except ImportError:  # pragma: no cover
    x509 = None


SCRIPT = Path(__file__).resolve().parents[1] / "roles/galaxy_k8s_deployment/files/check_ca_cert.sh"


def make_cert(path, cn, days=365, start_days=-2, ca=True):
    """Write a self-signed certificate; ``ca`` sets the basicConstraints CA flag."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    now = datetime.datetime.now(datetime.timezone.utc)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])
    builder = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now + datetime.timedelta(days=start_days))
        .not_valid_after(now + datetime.timedelta(days=days))
        .add_extension(x509.BasicConstraints(ca=ca, path_length=None), critical=True)
    )
    if not ca:
        builder = builder.add_extension(
            x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address("10.0.0.1"))]), critical=False
        )
    path.write_bytes(builder.sign(key, hashes.SHA256()).public_bytes(serialization.Encoding.PEM))
    return path


@unittest.skipUnless(x509, "cryptography is not installed")
class CheckCaCertTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def check(self, *args):
        return subprocess.run(["sh", str(SCRIPT), *map(str, args)], text=True, capture_output=True)

    def test_ca_certificate_passes_and_reports_identity(self):
        ca = make_cert(self.dir / "ca.crt", "Leonardo Galaxy Client CA")
        result = self.check(ca)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CN=Leonardo Galaxy Client CA", result.stdout)
        self.assertIn("notAfter=", result.stdout)
        self.assertIn("CA:TRUE", result.stdout)

    def test_a_leaf_certificate_is_accepted_as_a_trust_anchor_but_flagged(self):
        leaf = make_cert(self.dir / "leaf.crt", "leo-client", ca=False)
        result = self.check(leaf)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CA:FALSE", result.stdout)

    def test_unparseable_material_is_rejected(self):
        bad = self.dir / "bad.crt"
        bad.write_text("not a certificate\n")
        result = self.check(bad)
        self.assertEqual(result.returncode, 1)
        self.assertIn("does not parse", result.stderr)

    def test_expired_ca_is_rejected(self):
        ca = make_cert(self.dir / "old.crt", "old", days=-1)
        result = self.check(ca)
        self.assertEqual(result.returncode, 1)
        self.assertIn("expired", result.stderr)

    def test_not_yet_valid_ca_is_rejected(self):
        ca = make_cert(self.dir / "future.crt", "future", start_days=1)
        result = self.check(ca)
        self.assertEqual(result.returncode, 1)
        self.assertIn("not currently valid", result.stderr)

    def test_base64_encoded_pem_is_accepted(self):
        ca = make_cert(self.dir / "ca.crt", "b64")
        encoded = self.dir / "ca.b64"
        encoded.write_text(base64.b64encode(ca.read_bytes()).decode())
        result = self.check(encoded)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CN=b64", result.stdout)

    def test_a_chain_is_accepted_and_every_certificate_is_listed(self):
        root = make_cert(self.dir / "root.crt", "root")
        inter = make_cert(self.dir / "inter.crt", "intermediate")
        chain = self.dir / "chain.crt"
        chain.write_bytes(inter.read_bytes() + root.read_bytes())
        result = self.check(chain)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CN=intermediate", result.stdout)
        self.assertIn("CN=root", result.stdout)

    def test_requires_exactly_one_argument(self):
        self.assertEqual(self.check().returncode, 2)
        self.assertEqual(self.check("a", "b").returncode, 2)


if __name__ == "__main__":
    unittest.main()
