"""Exercise import-user resolution with the actual Ansible tasks and Helm values.

The import hook runs before UDT setup can read Galaxy's ConfigMap, so its account
must follow the values files at install time rather than the workspace owner.
"""
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / "roles/galaxy_k8s_deployment"
EMAIL = "shared-account@example.org"


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
class PostinstallUserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.tmp.cleanup)
        directory = Path(cls.tmp.name)
        source = yaml.safe_load((ROLE / "tasks/galaxy_application.yml").read_text())
        first = next(i for i, task in enumerate(source) if task["name"] == "Prepare Galaxy values files list")
        last = next(i for i, task in enumerate(source) if task["name"] == "Display Galaxy values files being used")
        resolution = source[first:last]
        helm = next(task for task in source if task["name"] == "Helm install Galaxy")
        defaults = yaml.safe_load((ROLE / "defaults/main.yml").read_text())

        def values_file(name, values):
            path = directory / f"{name}.yml"
            path.write_text(yaml.safe_dump(values))
            return str(path)

        def single_user(email):
            return {"configs": {"galaxy.yml": {"galaxy": {"single_user": email}}}}

        base = str(ROOT / "values/values.yml")
        profile = str(ROLE / "files/profiles/anvil.yaml")
        custom = values_file("custom", single_user(EMAIL))
        conflicting = values_file("conflicting", {
            **single_user(EMAIL),
            "postInstallJob": {"galaxyUser": "wrong-account@example.org"},
        })
        multiuser = values_file("multiuser", {
            **single_user(None),
            "postInstallJob": {"galaxyUser": "import-account@example.org"},
        })
        no_single_user = values_file("no-single-user", {
            "postInstallJob": {"galaxyUser": "import-account@example.org"},
        })
        disabled = values_file("disabled", {"postInstallJob": {"enabled": False}})
        cases = {
            "default": ([base], [profile], False),
            "custom": ([base, conflicting], [profile], False),
            "last_override": ([base, custom, values_file("last", single_user("last@example.org"))], [profile], False),
            "multiuser": ([base, multiuser], [profile], False),
            "no_single_user": ([no_single_user], [profile], False),
            "empty_single_user": ([base, values_file("empty", single_user(""))], [profile], False),
            "restore": ([base, custom], [profile], True),
            "disabled": ([base, custom, disabled], [profile], False),
            "no_profile": ([base, custom], [], False),
        }
        tasks = []
        for name, (files, profiles, restore) in cases.items():
            tasks.append({
                "name": f"Resolve imports for {name}",
                "vars": {
                    "galaxy_values_files": files,
                    "galaxy_import_profile": profiles,
                    "restore_galaxy": restore,
                    "_helm_values_base": helm["vars"]["_helm_values_base"],
                    "import_test_case": name,
                },
                "block": copy.deepcopy(resolution) + [{
                    "name": "Capture the import settings passed to Helm",
                    "ansible.builtin.set_fact": {
                        "_import_test_results": "{{ _import_test_results | default({}) | combine({import_test_case: {"
                        "'overrides': _helm_values_base.postInstallJob, "
                        "'postinstall': _galaxy_merged_values.postInstallJob | default({}) "
                        "| combine(_helm_values_base.postInstallJob) }}) }}",
                    },
                }],
            })
        result_path = directory / "results.json"
        tasks.append({"ansible.builtin.copy": {
            "dest": str(result_path),
            "content": "{{ _import_test_results | to_json }}",
            "mode": "0600",
        }})
        playbook = directory / "playbook.yml"
        playbook.write_text(yaml.safe_dump([{
            "hosts": "localhost",
            "gather_facts": False,
            "vars": {**defaults, "role_path": str(ROLE), "galaxy_user": "workspace-owner@example.org"},
            "tasks": tasks,
        }], sort_keys=False))
        env = dict(os.environ, ANSIBLE_LOCAL_TEMP=str(directory / "local"),
                   ANSIBLE_REMOTE_TEMP=str(directory / "remote"), ANSIBLE_NOCOLOR="1")
        result = subprocess.run([
            "ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
            "-e", f"ansible_python_interpreter={sys.executable}",
        ], cwd=ROOT, env=env, text=True, capture_output=True, timeout=90)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        cls.results = json.loads(result_path.read_text())

    def test_default_profile_keeps_its_imports_on_the_default_account(self):
        settings = self.results["default"]["postinstall"]
        self.assertEqual(settings["galaxyUser"], "default-user@galaxyproject.org")
        self.assertTrue(settings["enabled"])
        self.assertIn("rnaseq-de", settings["bootstrapConfig"])

    def test_single_user_overrides_a_conflicting_import_account(self):
        self.assertEqual(self.results["custom"]["postinstall"]["galaxyUser"], EMAIL)

    def test_last_values_file_selects_the_account(self):
        self.assertEqual(self.results["last_override"]["postinstall"]["galaxyUser"], "last@example.org")

    def test_multiuser_preserves_the_explicit_import_account(self):
        self.assertEqual(self.results["multiuser"]["postinstall"]["galaxyUser"], "import-account@example.org")
        self.assertEqual(self.results["multiuser"]["overrides"], {})

    def test_absent_single_user_preserves_the_explicit_import_account(self):
        self.assertEqual(self.results["no_single_user"]["postinstall"]["galaxyUser"], "import-account@example.org")
        self.assertEqual(self.results["no_single_user"]["overrides"], {})

    def test_empty_single_user_preserves_the_profile_account(self):
        self.assertEqual(self.results["empty_single_user"]["postinstall"]["galaxyUser"], "default-user@galaxyproject.org")
        self.assertEqual(self.results["empty_single_user"]["overrides"], {})

    def test_restore_still_disables_imports(self):
        self.assertEqual(self.results["restore"]["postinstall"]["galaxyUser"], EMAIL)
        self.assertFalse(self.results["restore"]["postinstall"]["enabled"])

    def test_disabled_imports_stay_disabled(self):
        self.assertEqual(self.results["disabled"]["postinstall"]["galaxyUser"], EMAIL)
        self.assertFalse(self.results["disabled"]["postinstall"]["enabled"])

    def test_no_profile_does_not_enable_the_import_job(self):
        self.assertEqual(self.results["no_profile"]["overrides"], {"galaxyUser": EMAIL})
        self.assertNotIn("enabled", self.results["no_profile"]["postinstall"])


if __name__ == "__main__":
    unittest.main()
