"""Run the actual in-container discovery script against representative disks."""
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "roles/galaxy_k8s_deployment/files/find_galaxy_data.sh"
FIRST = "11111111-1111-4111-8111-111111111111"
SECOND = "22222222-2222-4222-8222-222222222222"


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def discover(self, root=None):
        return subprocess.run(["sh", str(SCRIPT), str(root or self.root)], text=True, capture_output=True)

    def add(self, uuid, folder):
        (self.root / f"pvc-{uuid}" / folder).mkdir(parents=True)

    def test_both_supported_layouts(self):
        self.add(FIRST, "objects")
        self.add(SECOND, "files")
        result = self.discover()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(result.stdout.splitlines()), {FIRST, SECOND})

    def test_both_folders_in_one_volume_are_one_candidate(self):
        self.add(FIRST, "objects")
        self.add(FIRST, "files")
        self.assertEqual(self.discover().stdout.splitlines(), [FIRST])

    def test_unrelated_volumes_and_empty_directories_are_not_candidates(self):
        self.add(FIRST + "_galaxy_rabbitmq", "files")
        self.add("not-a-uuid", "objects")
        self.add(SECOND, "object_store_cache")
        result = self.discover()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_renamed_volumes_are_not_candidates(self):
        (self.root / f"retired-pvc-{FIRST}" / "objects").mkdir(parents=True)
        result = self.discover()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_empty_export_is_a_successful_empty_scan(self):
        result = self.discover()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_missing_export_is_an_error(self):
        result = self.discover(self.root / "missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertTrue(result.stderr)


if __name__ == "__main__":
    unittest.main()
