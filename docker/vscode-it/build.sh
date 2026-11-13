#!/bin/bash
# Build the VS Code (OpenVSCode Server) image for the Galaxy Interactive Tool.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REGISTRY="${REGISTRY:-ksuderman}"
IMAGE_NAME="${IMAGE_NAME:-galaxy-vscode}"
OPENVSCODE_VERSION="${OPENVSCODE_VERSION:-1.105.1}"
# Bump the suffix whenever the image changes without the editor version changing.
# Tags are never reused: the tool definition pins one, and a moved tag would be
# invisible to nodes that already pulled it (k8s_pull_policy: IfNotPresent).
TAG="${TAG:-${OPENVSCODE_VERSION}-3}"

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "Building the Galaxy VS Code interactive tool image..."
echo "  Base image:   gitpod/openvscode-server:${OPENVSCODE_VERSION}"
echo "  Output image: ${FULL_IMAGE}"
echo ""

docker build --platform linux/amd64 \
    --build-arg OPENVSCODE_VERSION="${OPENVSCODE_VERSION}" \
    -t "${FULL_IMAGE}" .

echo ""
echo "Build complete: ${FULL_IMAGE}"
echo ""
echo "To push to Docker Hub:"
echo "  docker push ${FULL_IMAGE}"
echo ""
echo "Then point the tool at it in mixins/vscode-it.yml:"
echo "  <container type=\"docker\">${FULL_IMAGE}</container>"
