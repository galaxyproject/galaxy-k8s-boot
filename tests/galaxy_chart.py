"""Render the Galaxy chart the way the playbook installs it.

Uses the role's pinned chart version and values files, plus the job limits
template the playbook merges into the Helm values, filled from role defaults.
Run as a script to print the manifest.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import jinja2
import yaml


REPO = Path(__file__).resolve().parents[1]
DEFAULTS = REPO / "roles/galaxy_k8s_deployment/defaults/main.yml"
JOB_LIMITS_TEMPLATE = REPO / "templates/galaxy_job_limits_values.yml.j2"


def chart_source():
    defaults = yaml.safe_load(DEFAULTS.read_text())
    repo_name, chart = defaults["galaxy_chart"].split("/")
    repo_url = next(r["url"] for r in defaults["helm_repositories"] if r["name"] == repo_name)
    return chart, repo_url, defaults["galaxy_chart_version"]


def render():
    defaults = yaml.safe_load(DEFAULTS.read_text())
    chart, repo_url, version = chart_source()
    with tempfile.TemporaryDirectory() as tmp:
        job_limits = Path(tmp) / "job_limits.yml"
        template = jinja2.Template(JOB_LIMITS_TEMPLATE.read_text(), undefined=jinja2.StrictUndefined)
        job_limits.write_text(template.render(defaults))
        values_args = []
        for values_file in defaults["galaxy_values_files"] + [str(job_limits)]:
            values_args += ["-f", str(REPO / values_file)]
        return subprocess.run(
            ["helm", "template", "galaxy", chart, "--repo", repo_url, "--version", version, *values_args],
            text=True, capture_output=True, check=True, timeout=120,
        ).stdout


def image():
    chart, repo_url, version = chart_source()
    values = subprocess.run(
        ["helm", "show", "values", chart, "--repo", repo_url, "--version", version],
        text=True, capture_output=True, check=True, timeout=120,
    ).stdout
    settings = yaml.safe_load(values)["image"]
    return f"{settings['repository']}:{settings['tag']}"


if __name__ == "__main__":
    print(image() if sys.argv[1:] == ["image"] else render())
