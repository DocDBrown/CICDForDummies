#!/bin/bash

# Example Usage: ./go-ci.sh "fix: update test suite"

# Check if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $(basename "$0") [commit-message]"
    echo "If no commit message is provided, uses 'passing tests' as default."
    exit 0
fi

DEFAULT_COMMIT_MSG="passing tests"
COMMIT_MSG="${1:-$DEFAULT_COMMIT_MSG}"

# Get module name
MODULE=$(go list -m)
if [ -z "$MODULE" ]; then
    echo "Failed to get module name." >&2
    exit 1
fi

# Run go mod verify
echo "Verifying module checksums..."
go mod verify
MOD_VERIFY_RESULT=$?
if [ $MOD_VERIFY_RESULT -ne 0 ]; then
    echo "Go module verification failed." >&2
    exit $MOD_VERIFY_RESULT
fi

# Run go mod tidy
echo "Syncing go.mod with go mod tidy..."
go mod tidy
MOD_TIDY_RESULT=$?
if [ $MOD_TIDY_RESULT -ne 0 ]; then
    echo "go mod tidy failed: fix dependency configuration." >&2
    exit $MOD_TIDY_RESULT
fi

# Check if Gitleaks image is available
echo "Checking Gitleaks container image..."
if ! podman inspect docker.io/zricethezav/gitleaks > /dev/null 2>&1; then
    echo "Gitleaks image not found. Pull it first with:"
    echo "  podman pull docker.io/zricethezav/gitleaks"
    exit 1
fi

# Run Gitleaks scan
echo "Scanning for secrets with Gitleaks..."
GITLEAKS_LOG="gitleaks.output"

podman run --rm \
    --volume "$(pwd)":/src:Z \
    --workdir /src \
    docker.io/zricethezav/gitleaks \
    gitleaks detect --source=/src --verbose > "$GITLEAKS_LOG" 2>&1

GITLEAKS_EXIT_CODE=$?

if [ -f "$GITLEAKS_LOG" ]; then
    cat "$GITLEAKS_LOG"
    rm -f "$GITLEAKS_LOG"
fi

if [ $GITLEAKS_EXIT_CODE -ne 0 ]; then
    echo "Gitleaks detected potential secrets. Fix before committing." >&2
    exit 1
fi

# Discover Go test packages
echo "Discovering test packages..."
mapfile -t PKGS < <(go list ./...)
if [ ${#PKGS[@]} -eq 0 ]; then
    echo "No packages found to test." >&2
    exit 1
fi

# Run tests
echo "Running tests..."
go test "${PKGS[@]}"
TEST_RESULT=$?
if [ $TEST_RESULT -ne 0 ]; then
    echo "Tests failed. Aborting commit." >&2
    exit $TEST_RESULT
fi

# Run go fmt
echo "Running go fmt..."
go fmt ./...
FMT_RESULT=$?
if [ $FMT_RESULT -ne 0 ]; then
    echo "go fmt failed." >&2
    exit $FMT_RESULT
fi

# Run go vet
echo "Running go vet..."
go vet
VET_RESULT=$?
if [ $VET_RESULT -ne 0 ]; then
    echo "go vet failed." >&2
    exit $VET_RESULT
fi

# Run gosec
echo "Running gosec (security scanner)..."
if ! command -v gosec > /dev/null 2>&1; then
    echo "gosec not found. Install with:"
    echo "  go install github.com/securego/gosec/v2/cmd/gosec@latest"
    exit 1
fi

gosec ./...
GOSEC_RESULT=$?
if [ $GOSEC_RESULT -ne 0 ]; then
    echo "gosec found potential security issues." >&2
    exit $GOSEC_RESULT
fi

# Run govulncheck
echo "Running govulncheck (vulnerability scanner)..."
if ! command -v govulncheck > /dev/null 2>&1; then
    echo "govulncheck not found. Install with:"
    echo "  go install golang.org/x/vuln/cmd/govulncheck@latest"
    exit 1
fi

govulncheck ./...
VULNCHECK_RESULT=$?
if [ $VULNCHECK_RESULT -ne 0 ]; then
    echo "govulncheck reported vulnerabilities." >&2
    exit $VULNCHECK_RESULT
fi

# Run golangci-lint
echo "Running golangci-lint..."
if ! command -v golangci-lint > /dev/null 2>&1; then
    echo "golangci-lint not found. Install with:"
    echo "  go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"
    exit 1
fi

golangci-lint run
LINT_RESULT=$?
if [ $LINT_RESULT -ne 0 ]; then
    echo "golangci-lint failed." >&2
    exit $LINT_RESULT
fi

# Final Git actions
echo "Staging and committing changes..."
git add -A
GIT_ADD_RESULT=$?
if [ $GIT_ADD_RESULT -ne 0 ]; then
    echo "git add failed." >&2
    exit $GIT_ADD_RESULT
fi

git commit -m "$COMMIT_MSG" && git push
GIT_COMMIT_OR_PUSH_RESULT=$?
if [ $GIT_COMMIT_OR_PUSH_RESULT -eq 0 ]; then
    echo "Successfully committed and pushed."
    exit 0
else
    echo "git commit or git push failed." >&2
    exit $GIT_COMMIT_OR_PUSH_RESULT
fi
