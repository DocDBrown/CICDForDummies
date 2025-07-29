#!/bin/bash

# Example Usage: ./git.sh "fix: update test suite"

# Check for help request
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $(basename "$0") [commit-message]"
    echo "Run unit tests (excluding ./e2e_tests and ./integration_tests) and commit/push if they pass."
    echo "If no commit message is provided, uses 'passing tests' as default."
    exit 0
fi

DEFAULT_COMMIT_MSG="passing tests"
COMMIT_MSG="${1:-$DEFAULT_COMMIT_MSG}"

# Get module name
MODULE=$(go list -m)
if [ -z "$MODULE" ]; then
    echo "Failed to get module name."
    exit 1
fi

# Build list of test packages, excluding e2e_tests and integration_tests
echo "Discovering test packages (excluding ./e2e_tests and ./integration_tests)..."
mapfile -t PKGS < <(go list ./... | grep -v "^${MODULE}/e2e_tests" | grep -v "^${MODULE}/integration_tests")

if [ ${#PKGS[@]} -eq 0 ]; then
    echo "No packages found to test."
    exit 1
fi

# Run tests on found packages
echo "Running tests on:"
printf '  %s\n' "${PKGS[@]}"
go test "${PKGS[@]}"
TEST_RESULT=$?

# Check test result
if [ $TEST_RESULT -eq 0 ]; then
    echo "All tests passed. Committing and pushing changes..."
    git add -A
    if git commit -m "$COMMIT_MSG" && git push; then
        echo "Successfully pushed changes."
        exit 0
    else
        echo "Commit or push failed."
        exit 1
    fi
else
    echo "Tests failed. Aborting commit and push."
    exit 1
fi
