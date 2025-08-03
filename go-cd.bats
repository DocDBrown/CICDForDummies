#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

SCRIPT="./go-cd.sh"

@test "script is executable and has no syntax errors" {
  run bash -n "$SCRIPT"
  assert_success
}

@test "IMAGE_NAME is set to registry.localhost:80/reasoning" {
  run grep -E '^IMAGE_NAME="registry\.localhost:80/reasoning"$' "$SCRIPT"
  assert_success
}

@test "TAG falls back to git short SHA when CI_COMMIT_SHA is unset" {
  # Check for CI_COMMIT_SHA fallback
  run grep -q 'CI_COMMIT_SHA:-\$(git rev-parse --short HEAD)' "$SCRIPT"
  assert_success
}

@test "podman build is invoked with -t \"\${FULL_IMAGE}\"" {
  run grep -E 'podman build -t "\$\{FULL_IMAGE\}" \.' "$SCRIPT"
  assert_success
}

@test "podman push is invoked for FULL_IMAGE" {
  run grep -E 'podman push "\$\{FULL_IMAGE\}"' "$SCRIPT"
  assert_success
}

@test "kubectl set image updates deployment/reasoning" {
  run grep -E 'kubectl -n default set image deployment/reasoning' "$SCRIPT"
  assert_success
}
