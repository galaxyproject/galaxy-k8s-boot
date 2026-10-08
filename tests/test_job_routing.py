"""Route representative jobs through TPV using the chart's rendered job config.

The chart is rendered as the playbook installs it (see galaxy_chart.py), then
TPV maps mock jobs as Galaxy would at runtime, including the shared TPV
database that production also loads.

TPV imports Galaxy at runtime, so run this inside the Galaxy image the chart
deploys: tests/run_job_routing_tests.sh. That script renders the chart on the
host and passes the manifest in through RENDERED_CHART. Without TPV, or
without helm or a rendered manifest, the tests are skipped.
"""
import importlib.util
import logging
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import yaml

import galaxy_chart


LARGE_TOOL = "test_large_tool"
LARGE_TOOL_RULES = {"tools": {LARGE_TOOL: {"cores": 4, "mem": 16}}}


def rendered_config_maps():
    if os.environ.get("RENDERED_CHART"):
        manifest = Path(os.environ["RENDERED_CHART"]).read_text()
    else:
        manifest = galaxy_chart.render()
    return [doc for doc in yaml.safe_load_all(manifest) if doc and doc.get("kind") == "ConfigMap"]


@unittest.skipUnless(shutil.which("helm") or os.environ.get("RENDERED_CHART"),
                     "helm or a rendered chart is required")
@unittest.skipUnless(importlib.util.find_spec("tpv"), "TPV and Galaxy are required")
class RoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Galaxy modules call logging.basicConfig(level=DEBUG) on import, which
        # is a no-op once the root logger has a handler.
        logging.basicConfig(level=logging.WARNING)
        tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(tmp.cleanup)
        workdir = Path(tmp.name)
        config_maps = rendered_config_maps()
        job_conf_text = next(cm["data"]["job_conf.yml"] for cm in config_maps
                             if "job_conf.yml" in cm.get("data", {}))
        rules = next(cm["data"]["tpv_rules_local.yml"] for cm in config_maps
                     if cm["metadata"]["name"] == "galaxy-job-rules")
        cls.job_conf = workdir / "job_conf.yml"
        cls.job_conf.write_text(job_conf_text)
        # The job config lists the rules by their path inside the Galaxy pod.
        dispatcher = yaml.safe_load(job_conf_text)["execution"]["environments"]["tpv_dispatcher"]
        cls.tpv_configs = []
        for config in dispatcher["tpv_config_files"]:
            if config.endswith("tpv_rules_local.yml"):
                local_rules = workdir / "tpv_rules_local.yml"
                local_rules.write_text(rules)
                config = str(local_rules)
            cls.tpv_configs.append(config)
        large_tool_rules = workdir / "large_tool_rules.yml"
        large_tool_rules.write_text(yaml.safe_dump(LARGE_TOOL_RULES))
        cls.tpv_configs.append(str(large_tool_rules))

    def route(self, tool_id, **tool_options):
        from tpv.commands.dryrunner import TPVDryRunner
        from tpv.commands.test import mock_galaxy

        tool = mock_galaxy.Tool(tool_id, **tool_options)
        # The chart's force_default_container_for_built_in_tools rule reads
        # attributes that TPV's mock tool lacks.
        tool.is_datatype_converter = False
        tool.requirements = SimpleNamespace(packages=[])
        runner = TPVDryRunner(
            job_conf=str(self.job_conf), tpv_confs=self.tpv_configs,
            user=mock_galaxy.User("anvil", "default-user@galaxyproject.org"),
            tool=tool, job=mock_galaxy.Job(),
        )
        destination, _ = runner.run()
        return destination

    def test_small_tool_runs_on_kubernetes(self):
        destination = self.route("cat1")
        self.assertEqual(destination.runner, "k8s")
        self.assertNotIn("require_container", destination.params)

    def test_large_tool_runs_on_gcp_batch(self):
        destination = self.route(LARGE_TOOL)
        self.assertEqual(destination.runner, "gcp_batch")

    def test_user_defined_tool_requires_a_container(self):
        from tpv.commands.test import mock_galaxy

        destination = self.route(
            "authored-tool-id", tool_type="user_defined",
            dynamic_tool=mock_galaxy.DynamicTool("6f1d0b6a-3c55-4a8e-9a0e-2f1f4a1b9c11"),
        )
        self.assertIn(destination.runner, ("k8s", "gcp_batch"))
        self.assertIs(destination.params.get("require_container"), True)


if __name__ == "__main__":
    unittest.main()
