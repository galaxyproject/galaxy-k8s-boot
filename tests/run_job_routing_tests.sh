#!/usr/bin/env bash
# Run tests/test_job_routing.py inside the Galaxy image the pinned chart
# deploys, so TPV and Galaxy match production. The image has no helm, so the
# chart is rendered here and passed in. Requires docker, helm, and PyYAML.
set -euo pipefail

tests=$(cd "$(dirname "$0")" && pwd)
rendered=$(mktemp)
trap 'rm -f "$rendered"' EXIT
chmod 644 "$rendered"

image=$(python3 "$tests/galaxy_chart.py" image)
python3 "$tests/galaxy_chart.py" > "$rendered"

echo "Running routing tests in $image"
docker run --rm --platform linux/amd64 \
  -v "$tests:/tests:ro" -v "$rendered:/rendered.yaml:ro" \
  -e RENDERED_CHART=/rendered.yaml -e PYTHONPATH=/galaxy/server/lib -e HOME=/tmp \
  "$image" /galaxy/server/.venv/bin/python -m unittest discover -s /tests -p test_job_routing.py -v
