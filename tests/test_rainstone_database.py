"""Run the database preparation tasks with local disks and mocked API reads."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml


ROLE = Path(__file__).resolve().parents[1] / "roles/galaxy_k8s_deployment"


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
class DatabasePreparationTests(unittest.TestCase):
    def prepare(self, retained=False, existing=False, plugins=None, incomplete=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            disk = root / "disk"
            disk.mkdir()
            if retained:
                data = disk / "pvc-first_galaxy_rainstone-postgres-1/pgdata"
                data.mkdir(parents=True)
                if not incomplete:
                    (data / "PG_VERSION").write_text("17\n")
            tasks = yaml.safe_load((ROLE / "tasks/rainstone_database.yml").read_text())
            for task in tasks:
                if "kubernetes.core.k8s_info" in task:
                    del task["kubernetes.core.k8s_info"]
                    del task["register"]
                    task["ansible.builtin.set_fact"] = {
                        "_rainstone_database_cluster": {
                            "resources": [{"spec": {"plugins": plugins or []}}] if existing else [],
                        },
                    }
                if "ansible.builtin.include_tasks" in task:
                    del task["ansible.builtin.include_tasks"]
                    task["ansible.builtin.set_fact"] = {"plugin_prepared": True}
            if existing:
                expected = plugins or []
            else:
                expected = [{"name": "skip-initdb"}] if retained else []
            tasks.append({"ansible.builtin.assert": {"that": [
                "_rainstone_database_plugins == expected_plugins",
                "(plugin_prepared | default(false)) == (expected_plugins | length > 0)",
            ]}})
            play = [{
                "hosts": "localhost", "connection": "local", "gather_facts": False,
                "vars": {
                    "role_path": str(ROLE), "rainstone_values": {},
                    "ansible_remote_tmp": str(root / "remote"),
                    "postgres_storage_disk_path": str(disk),
                    "kubeconfig_path": "unused", "cnpg_skip_initdb_plugin_name": "skip-initdb",
                    "expected_plugins": expected,
                },
                "tasks": tasks,
            }]
            path = root / "play.yml"
            path.write_text(yaml.safe_dump(play))
            return subprocess.run(
                ["ansible-playbook", "-i", "localhost,", str(path)],
                env={**os.environ, "ANSIBLE_LOCAL_TEMP": str(root / "ansible")},
                capture_output=True, text=True,
            )

    def test_fresh_install_without_rainstone_values(self):
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_retained_database_enables_plugin(self):
        result = self.prepare(retained=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_existing_fresh_cluster_stays_without_plugin(self):
        result = self.prepare(existing=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_existing_restored_cluster_keeps_plugin(self):
        result = self.prepare(existing=True, plugins=[{"name": "skip-initdb"}])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_incomplete_data_stops_preparation(self):
        result = self.prepare(retained=True, incomplete=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Incomplete Rainstone database", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
