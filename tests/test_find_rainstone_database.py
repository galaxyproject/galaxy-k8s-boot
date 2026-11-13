"""Exercise retained-disk discovery using the script executed by Ansible."""
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "roles/galaxy_k8s_deployment/files/find_rainstone_database.sh"


class RainstoneDatabaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def directory(self, identifier="first", claim="rainstone-postgres-1", namespace="galaxy"):
        path = self.root / f"pvc-{identifier}_{namespace}_{claim}"
        (path / "pgdata").mkdir(parents=True)
        (path / "pgdata/PG_VERSION").write_text("17\n")
        return path

    def discover(self, root=None):
        return subprocess.run(
            ["sh", str(SCRIPT), str(root or self.root), "galaxy", "rainstone-postgres-1"],
            capture_output=True, text=True,
        )

    def test_old_standalone_and_galaxy_data_are_ignored(self):
        self.directory(claim="rainstone-postgres")
        self.directory(claim="galaxy-postgres-1")
        self.directory(namespace="another")
        result = self.discover()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_repeated_restore_symlinks_are_one_database(self):
        data = self.directory()
        (self.root / "pvc-second_galaxy_rainstone-postgres-1").symlink_to(data)
        result = self.discover()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(data))

    def test_multiple_databases_fail_instead_of_selecting_one(self):
        self.directory()
        self.directory("second")
        self.assertNotEqual(self.discover().returncode, 0)

    def test_empty_directory_cannot_hide_a_retained_database(self):
        self.directory()
        (self.root / "pvc-second_galaxy_rainstone-postgres-1").mkdir()
        self.assertNotEqual(self.discover().returncode, 0)

    def test_broken_alias_does_not_start_a_fresh_database(self):
        (self.root / "pvc-second_galaxy_rainstone-postgres-1").symlink_to(self.root / "missing")
        self.assertNotEqual(self.discover().returncode, 0)

    def test_incomplete_data_fails_instead_of_starting_fresh(self):
        data = self.directory()
        (data / "pgdata/PG_VERSION").unlink()
        self.assertNotEqual(self.discover().returncode, 0)

    def test_empty_disk_is_fresh_but_missing_disk_is_an_error(self):
        self.assertEqual(self.discover().stdout, "")
        self.assertNotEqual(self.discover(self.root / "missing").returncode, 0)


if __name__ == "__main__":
    unittest.main()
