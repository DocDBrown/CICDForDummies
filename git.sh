#!/bin/bash

# Example Usage: ./git.sh "fix: update test suite"

# Check for help request
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
    echo "Failed to get module name."
    exit 1
fi

# Build list of test packages (now including all)
echo "Discovering test packages..."
mapfile -t PKGS < <(go list ./...)
if [ ${#PKGS[@]} -eq 0 ]; then
    echo "No packages found to test."
    exit 1
fi

# Run tests on found packages
echo "Running tests on:"
printf ' %s\n' "${PKGS[@]}"
go test "${PKGS[@]}"
TEST_RESULT=$?

# Check test result
if [ $TEST_RESULT -eq 0 ]; then
    echo "All tests passed. Linting code..."

    # Format code using go fmt
    echo "Running go fmt..."
    go fmt ./...
    FMT_RESULT=$?
    if [ $FMT_RESULT -ne 0 ]; then
        echo "Go fmt failed."
        exit $FMT_RESULT
    fi

    # Run go vet for static analysis
    echo "Running go vet..."
    go vet
    VET_RESULT=$?
    if [ $VET_RESULT -ne 0 ]; then
        echo "Go vet failed."
        exit $VET_RESULT
    fi

    # Stage all changes (including formatted code)
    git add -A

    # Commit and push
    echo "Linting succeeded. Committing and pushing changes..."
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