# VS Code (OpenVSCode Server) image for the Galaxy "VS Code" Interactive Tool
# (mixins/vscode-it.yml).
#
# The stock gitpod/openvscode-server image is only an editor plus a shell: no
# Python, no conda, no cloud tooling. This image adds what a Galaxy user needs to
# do analysis in the IDE and to move data between the workspace, the history and
# (on Terra) the workspace bucket:
#
#   - python3 with bioblend (Galaxy API) and ipykernel (run .ipynb files with the
#     Jupyter extension)
#   - micromamba for conda-forge / bioconda packages
#   - R from conda-forge with languageserver (R extension), IRkernel (R notebooks
#     with the Jupyter extension) and httpgd (plots in the R extension)
#   - the Google Cloud CLI (gcloud, gsutil). Inside the cluster it authenticates
#     through the GCE metadata server as the VM's service account, which on Terra
#     is the workspace pet service account. No credentials are mounted or copied.
#   - the Python, Jupyter and R extensions, pre-installed from Open VSX
#   - start.sh, which sets up HOME, the workspace README and the server flags, and
#     the galaxy-get / galaxy-put helpers
#
# Galaxy runs the pod/container as the Galaxy job uid with the tool command as
# its script, so everything the tool needs at runtime must be world-readable, and
# anything written must go under the job working directory (start.sh points HOME
# there).

ARG OPENVSCODE_VERSION=1.105.1
FROM gitpod/openvscode-server:${OPENVSCODE_VERSION}

USER root
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apt-transport-https \
        bzip2 \
        ca-certificates \
        curl \
        git-lfs \
        gnupg \
        jq \
        less \
        nano \
        python3 \
        python3-pip \
        python3-venv \
        unzip \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# jupyter_client provides `jupyter kernelspec`, which IRkernel's installspec needs
# and which the Jupyter extension uses to find kernels.
RUN pip3 install --no-cache-dir bioblend ipykernel jupyter_client

# micromamba: a single static binary. The environments root for users' own
# environments is set per session by start.sh (MAMBA_ROOT_PREFIX under the job's
# HOME).
RUN curl -fsSL https://micro.mamba.pm/api/micromamba/linux-64/latest \
        | tar -xj -C /usr/local/bin --strip-components=1 bin/micromamba

# R, as binary packages from conda-forge, in a system-wide environment. It goes at
# the END of PATH so that the environment's own python never shadows /usr/bin/python3
# (the Jupyter extension's default interpreter).
ENV R_ENV=/opt/conda/envs/r
RUN micromamba create -y -r /opt/conda -n r -c conda-forge \
        r-base r-languageserver r-irkernel r-httpgd \
    && micromamba clean -y -a \
    && PATH="${PATH}:${R_ENV}/bin" Rscript -e 'IRkernel::installspec(user = FALSE)' \
    && jupyter kernelspec list | grep -q ir \
    && chmod -R a+rX /opt/conda
ENV PATH=${PATH}:${R_ENV}/bin

# Pre-install extensions into a shared, world-writable directory. The pod does not
# run as this image's user, so the directory must be writable by any uid for the
# server to record extension state and for users to add extensions during a
# session (those additions live in the container and vanish with it).
ENV GALAXY_VSCODE_EXTENSIONS=/opt/openvscode-server/extensions
RUN mkdir -p "${GALAXY_VSCODE_EXTENSIONS}" \
    && for ext in ms-python.python ms-toolsai.jupyter REditorSupport.r; do \
        /home/.openvscode-server/bin/openvscode-server \
            --extensions-dir "${GALAXY_VSCODE_EXTENSIONS}" \
            --server-data-dir /tmp/build-server-data \
            --user-data-dir /tmp/build-user-data \
            --install-extension "${ext}" ; \
    done \
    && rm -rf /tmp/build-server-data /tmp/build-user-data \
    && chmod -R a+rwX "${GALAXY_VSCODE_EXTENSIONS}"

COPY start.sh /opt/galaxy-vscode/start.sh
COPY bin/ /opt/galaxy-vscode/bin/
RUN chmod -R a+rX /opt/galaxy-vscode

ENV PATH=/opt/galaxy-vscode/bin:${PATH}

# Sanity checks: fail the build rather than the first IT launch.
RUN python3 -c "import bioblend, ipykernel" \
    && gcloud --version >/dev/null \
    && micromamba --version >/dev/null \
    && [ "$(command -v python3)" = /usr/bin/python3 ] \
    && Rscript -e 'library(languageserver); library(IRkernel); library(httpgd)' \
    && /home/.openvscode-server/bin/openvscode-server --extensions-dir "${GALAXY_VSCODE_EXTENSIONS}" --list-extensions | grep -q ms-python.python \
    && /home/.openvscode-server/bin/openvscode-server --extensions-dir "${GALAXY_VSCODE_EXTENSIONS}" --list-extensions | grep -qi reditorsupport.r

USER openvscode-server

# No ENTRYPOINT. Galaxy's Docker runner starts the container as
# `docker run ... <image> /bin/sh tool_script.sh` without --entrypoint, so an
# entrypoint would swallow the tool script (no input links, no EP_PATH) and the
# base image's own entrypoint would append it to the stock server's flags. The
# Kubernetes runner sets command/args explicitly and does not care either way.
# A bare `docker run` with no command still starts the server via CMD; it needs
# EP_PATH set and a writable cwd:
#   docker run -e EP_PATH=/galaxy/its/ep/1/t/ -w /jobdir -v $PWD:/jobdir -p 3000:3000 <image>
ENTRYPOINT []
CMD ["/opt/galaxy-vscode/start.sh"]
