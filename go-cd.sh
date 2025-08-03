#!/usr/bin/env bash
set -euo pipefail

# variables
IMAGE_NAME="registry.localhost:80/reasoning"
TAG=${CI_COMMIT_SHA:-$(git rev-parse --short HEAD)}
FULL_IMAGE="${IMAGE_NAME}:${TAG}"

# 1. Build
podman build -t "${FULL_IMAGE}" .

# 2. Push
echo "Pushing ${FULL_IMAGE}…"
podman push "${FULL_IMAGE}"

# 3. Update k8s Deployment
kubectl -n default set image deployment/reasoning \
  reasoning="${FULL_IMAGE}" \
  --record

echo "Deployed ${FULL_IMAGE} to k3s."
