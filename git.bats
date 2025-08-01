#!/usr/bin/env bats

SCRIPT="./git.sh"

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    cd "$TEST_TEMP_DIR" || exit 1

    # ✅ COPY the script into the temp directory
    cp "$BATS_TEST_DIRNAME/git.sh" ./git.sh
    chmod +x ./git.sh  # Ensure it's executable

    # Create fake git repo
    git init > /dev/null 2>&1
    touch dummy.go
    mkdir -p e2e_tests integration_tests utils api
    touch e2e_tests/e2e_test.go
    touch integration_tests/non_test_gen_test.go
    touch utils/helper_test.go
    touch api/server_test.go

    # Create go.mod
    echo "module mockmodule" > go.mod

    git add . && git commit -m "initial" --no-gpg-sign > /dev/null 2>&1

    # Set up mock bin
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    # Default test success
    export GO_TEST_RESULT=0
    export GO_FMT_RESULT=0
    export GO_VET_RESULT=0
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# Helper to start mocks
start_mocks() {
    # Mock go
    cat << 'EOF' > "$BATS_TEST_TMPDIR/bin/go"
#!/usr/bin/env bash
echo "go $*" >&2  # Log command to stderr

case "$1" in
    "list")
        if [[ "$*" == *"-m"* ]]; then
            echo "mockmodule"
            exit 0
        elif [[ "$*" == *"./..."* ]]; then
            echo "mockmodule/utils"
            echo "mockmodule/api"
            echo "mockmodule/e2e_tests"
            echo "mockmodule/integration_tests"
            exit 0
        else
            echo "unknown go list args: $*" >&2
            exit 1
        fi
        ;;
    "test")
        echo "go test $*" >&2
        exit "$GO_TEST_RESULT"
        ;;
    "fmt")
        echo "go fmt $*" >&2
        exit "$GO_FMT_RESULT"
        ;;
    "vet")
        echo "go vet $*" >&2
        exit "$GO_VET_RESULT"
        ;;
    *)
        echo "go $*" >&2
        exit 0
        ;;
esac
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/go"

    # Mock git
    cat << 'EOF' > "$BATS_TEST_TMPDIR/bin/git"
#!/usr/bin/env bash
echo "git $*"
case "$1" in
    add)    exit 0 ;;
    commit) exit 0 ;;
    push)   exit 0 ;;
    *)      exit 0 ;;
esac
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
}

# Helper: run script with mocks started
run_script() {
    start_mocks
    SCRIPT_NAME="$(basename "$SCRIPT")"
    run bash "./$SCRIPT_NAME" "$@"
}

# -------------------------------
# TEST: Custom commit message is used
# -------------------------------
@test "CustomCommitMessageUsedWhenProvided" {
    export GO_TEST_RESULT=0
    run_script "my custom msg"

    [ "$status" -eq 0 ]
    [[ "$output" == *"git commit -m my custom msg"* ]]
}

# -------------------------------
# TEST: Tests pass triggers git add, commit, push after linting
# -------------------------------
@test "TestsPassTriggersGitCommitAndPush" {
    export GO_TEST_RESULT=0
    run_script

    [ "$status" -eq 0 ]
    [[ "$output" == *"git add -A"* ]]
    [[ "$output" == *"git commit"* ]]
    [[ "$output" == *"git push"* ]]
    [[ "$output" == *"Successfully pushed changes"* ]]
    [[ "$output" == *"Running go fmt..."* ]]
    [[ "$output" == *"Running go vet..."* ]]
}

# -------------------------------
# TEST: Test failure prevents git operations
# -------------------------------
@test "TestsFailPreventsGitOperations" {
    export GO_TEST_RESULT=1
    run_script "some message"

    [ "$status" -eq 1 ]
    [[ ! "$output" == *"git add -A"* ]]
    [[ ! "$output" == *"git commit"* ]]
    [[ ! "$output" == *"git push"* ]]
    [[ "$output" == *"Tests failed. Aborting commit and push."* ]]
}

# -------------------------------
# TEST: go fmt failure aborts commit
# -------------------------------
@test "GoFmtFailsAbortsCommit" {
    export GO_TEST_RESULT=0
    export GO_FMT_RESULT=1
    run_script

    [ "$status" -eq 1 ]
    [[ "$output" == *"Go fmt failed."* ]]
    [[ ! "$output" == *"git add -A"* ]]
    [[ ! "$output" == *"git commit"* ]]
    [[ ! "$output" == *"git push"* ]]
}

# -------------------------------
# TEST: go vet failure aborts commit
# -------------------------------
@test "GoVetFailsAbortsCommit" {
    export GO_TEST_RESULT=0
    export GO_FMT_RESULT=0
    export GO_VET_RESULT=1
    run_script

    [ "$status" -eq 1 ]
    [[ "$output" == *"Go vet failed."* ]]
    [[ ! "$output" == *"git add -A"* ]]
    [[ ! "$output" == *"git commit"* ]]
    [[ ! "$output" == *"git push"* ]]
}