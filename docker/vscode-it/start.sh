#!/bin/bash
#
# Entry point for the Galaxy "VS Code" Interactive Tool. Galaxy runs the tool
# command in the job working directory as the Galaxy job uid, with these
# variables injected by the tool definition (mixins/vscode-it.yml):
#
#   EP_PATH     the full path Galaxy routes to this entry point, which the server
#               must serve from because the Ingress forwards the path unchanged
#   GALAXY_URL  the Galaxy API endpoint reachable from inside the cluster
#   API_KEY     the launching user's API key
#   HISTORY_ID  the history the tool was launched from
#
# Everything written at runtime goes under the job working directory: it is the
# only writable location on the shared volume, and workspace/outputs is what
# Galaxy collects when the tool is stopped.

set -euo pipefail

: "${EP_PATH:?EP_PATH must be set by Galaxy (inject=\"entry_point_path_for_label\")}"

JOB_DIR="$PWD"
WORKSPACE="$JOB_DIR/workspace"
export HOME="$JOB_DIR/home"
export MAMBA_ROOT_PREFIX="$HOME/micromamba"

mkdir -p "$HOME/data/User" "$HOME/server" "$WORKSPACE/inputs" "$WORKSPACE/outputs"

# Shell for the integrated terminal.
cat > "$HOME/.bashrc" <<EOF
export PATH="/opt/galaxy-vscode/bin:\$PATH"
export MAMBA_ROOT_PREFIX="$MAMBA_ROOT_PREFIX"
eval "\$(micromamba shell hook -s bash)"
cd "$WORKSPACE"
PS1='\w \$ '
EOF
echo 'source ~/.bashrc' > "$HOME/.bash_profile"

# Editor defaults, written once so a user's own changes during the session win.
if [[ ! -e "$HOME/data/User/settings.json" ]]; then
    cat > "$HOME/data/User/settings.json" <<EOF
{
    "python.defaultInterpreterPath": "/usr/bin/python3",
    "r.rpath.linux": "${R_ENV:-/opt/conda/envs/r}/bin/R",
    "r.rterm.linux": "${R_ENV:-/opt/conda/envs/r}/bin/R",
    "r.plot.useHttpgd": true,
    "telemetry.telemetryLevel": "off",
    "workbench.startupEditor": "readme",
    "workbench.tips.enabled": false,
    "extensions.autoUpdate": false,
    "security.workspace.trust.enabled": false
}
EOF
fi

# Orientation for the user. Written once; a user who edits it keeps the edits.
if [[ ! -e "$WORKSPACE/README.md" ]]; then
    cat > "$WORKSPACE/README.md" <<'EOF'
# Galaxy VS Code workspace

Galaxy started this VS Code session as an Interactive Tool. It runs inside your
Galaxy instance, next to your data.

## Folders

- `inputs/` holds the datasets you selected when launching the tool, linked
  read-only.
- `outputs/` is collected when you stop the tool from Galaxy (User > Active
  Interactive Tools). Every file saved here WITH a file extension, such as
  `notes.txt` or `result.tsv`, is imported into your history as a collection.

Nothing else survives: when the tool stops, the rest of the workspace, the
editor settings and any extensions you installed are discarded.

## Talking to Galaxy

Open a terminal (Terminal > New Terminal). These variables are set:

- `GALAXY_URL` is the Galaxy API endpoint reachable from here.
- `API_KEY` is your Galaxy API key.
- `HISTORY_ID` is the history this tool was launched from.

Two helpers use them:

```
galaxy-get <dataset>  [destination]   # copy a dataset from the history here
galaxy-put <file> [<file> ...]        # upload files to the history now
```

`<dataset>` is a history item number (the "3" in "3: my.fasta"), a dataset id
or an exact dataset name. For anything else, bioblend is installed:

```
python3 -c 'from bioblend.galaxy import GalaxyInstance; import os
gi = GalaxyInstance(os.environ["GALAXY_URL"], os.environ["API_KEY"])
print(gi.histories.show_history(os.environ["HISTORY_ID"])["name"])'
```

## What is installed

- `python3` with `bioblend` and `ipykernel`, so `.ipynb` notebooks run with the
  pre-installed Jupyter extension. Select `/usr/bin/python3` as the kernel.
- `R` and `Rscript` (conda-forge) with `languageserver` for the pre-installed R
  extension, `IRkernel` so notebooks can use the "R" kernel, and `httpgd` for
  plots. Add packages with `install.packages()` (they go under `~/R`, so they
  last for the session) or with micromamba from conda-forge (`r-tidyverse`) or
  bioconda (`bioconductor-deseq2`).
- `micromamba` for conda-forge and bioconda packages, for example
  `micromamba create -n work -c conda-forge -c bioconda samtools` and then
  `micromamba activate work`. Environments are created under `~/micromamba`.
- `git`, `git-lfs`, `jq`, `curl`, `nano`.
- `gcloud` and `gsutil`.

More extensions can be installed from the Extensions view (Open VSX registry).

## Google Cloud

`gcloud` and `gsutil` authenticate automatically as the service account of the
VM that Galaxy runs on. On Terra that is the workspace pet service account, so
`gcloud storage ls gs://<workspace bucket>` works without logging in. Check
with `gcloud auth list`.
EOF
fi

# Galaxy's Kubernetes runner forwards the request path unchanged, so the server
# must serve from the entry point path. The pre-installed extensions live in the
# image; the server records its state there too, which is why the directory is
# world-writable.
exec /home/.openvscode-server/bin/openvscode-server \
    --host 0.0.0.0 \
    --port 3000 \
    --without-connection-token \
    --server-base-path "$EP_PATH" \
    --server-data-dir "$HOME/server" \
    --user-data-dir "$HOME/data" \
    --extensions-dir "${GALAXY_VSCODE_EXTENSIONS:-/opt/openvscode-server/extensions}" \
    --disable-telemetry \
    --default-folder "$WORKSPACE"
