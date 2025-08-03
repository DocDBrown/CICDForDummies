#!/usr/bin/env bats

SCRIPT="./go-ci.sh"

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    cd "$TEST_TEMP_DIR" || exit 1

    cp "$BATS_TEST_DIRNAME/go-ci.sh" "$TEST_TEMP_DIR/go-ci.sh"
    chmod +x "$TEST_TEMP_DIR/go-ci.sh"

    git init > /dev/null 2>&1
    touch dummy.go
    mkdir -p e2e_tests integration_tests utils
    touch e2e_tests/e2e_test.go
    touch integration_tests/integration_test.go
    echo "module mockmodule" > go.mod
    git add . && git commit -m "initial" --no-gpg-sign > /dev/null 2>&1

    export BATS_TEST_BIN="$BATS_TEST_TMPDIR/mock_bin"
    mkdir -p "$BATS_TEST_BIN"
    export PATH="$BATS_TEST_BIN:$PATH"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

setup_mocks() {
    # Mock go
    cat <<'EOF' > "$BATS_TEST_BIN/go"
#!/usr/bin/env bash
echo "go $*" >&2
case "$1" in
    list)
        if [[ "$3" == "-m" ]]; then
            echo "mockmodule"
            exit 0
        else
            echo "mockmodule/utils"
            echo "mockmodule/e2e_tests"
            echo "mockmodule/integration_tests"
            exit 0
        fi
        ;;
    test)
        exit "${GO_TEST_RESULT:-0}"
        ;;
    fmt)
        exit "${GO_FMT_RESULT:-0}"
        ;;
    vet)
        exit "${GO_VET_RESULT:-0}"
        ;;
    mod)
        if [[ "$2" == "verify" ]]; then
            [[ "${GO_MOD_VERIFY_RESULT:-0}" -ne 0 ]] && echo "Go module verification failed." >&2
            exit "${GO_MOD_VERIFY_RESULT:-0}"
        elif [[ "$2" == "tidy" ]]; then
            [[ "${GO_MOD_TIDY_RESULT:-0}" -ne 0 ]] && echo "go mod tidy failed: fix dependency configuration." >&2
            exit "${GO_MOD_TIDY_RESULT:-0}"
        else
            exit 1
        fi
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$BATS_TEST_BIN/go"

    # Mock git
    cat <<'EOF' > "$BATS_TEST_BIN/git"
#!/usr/bin/env bash
echo "git $*" >&2
case "$1" in
    add)
        exit 0
        ;;
    commit)
        shift
        echo "git commit $*" >&2
        exit 0
        ;;
    push)
        echo "git push" >&2
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$BATS_TEST_BIN/git"

    # Mock podman
    cat <<'EOF' > "$BATS_TEST_BIN/podman"
#!/usr/bin/env bash
echo "podman $*" >&2
case "$1" in
    inspect)
        exit "${PODMAN_INSPECT_EXISTS:-1}"
        ;;
    run)
        if [[ "$*" == *"gitleaks"* ]]; then
            [[ "${GITLEAKS_EXIT_CODE:-0}" -ne 0 ]] && echo "Gitleaks detected potential secrets. Fix before committing." >&2
            exit "${GITLEAKS_EXIT_CODE:-0}"
        fi
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$BATS_TEST_BIN/podman"

    # Mock golangci-lint
    cat <<'EOF' > "$BATS_TEST_BIN/golangci-lint"
#!/usr/bin/env bash
echo "golangci-lint $*" >&2
[[ "${GOLANGCI_LINT_EXIT_CODE:-0}" -ne 0 ]] && echo "golangci-lint failed." >&2
exit "${GOLANGCI_LINT_EXIT_CODE:-0}"
EOF
    chmod +x "$BATS_TEST_BIN/golangci-lint"

    # Mock gosec
    cat <<'EOF' > "$BATS_TEST_BIN/gosec"
#!/usr/bin/env bash
echo "gosec $*" >&2
[[ "${GOSEC_EXIT_CODE:-0}" -ne 0 ]] && echo "gosec found potential security issues." >&2
exit "${GOSEC_EXIT_CODE:-0}"
EOF
    chmod +x "$BATS_TEST_BIN/gosec"

    # Mock govulncheck
    cat <<'EOF' > "$BATS_TEST_BIN/govulncheck"
#!/usr/bin/env bash
echo "govulncheck $*" >&2
[[ "${GOVULNCHECK_EXIT_CODE:-0}" -ne 0 ]] && echo "govulncheck reported vulnerabilities." >&2
exit "${GOVULNCHECK_EXIT_CODE:-0}"
EOF
    chmod +x "$BATS_TEST_BIN/govulncheck"
}

run_script() {
    setup_mocks
    run "$TEST_TEMP_DIR/go-ci.sh" "$@"
}

@test "HelpFlagWorks" {
    run_script "--help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: go-ci.sh"* ]]
}

@test "CustomCommitMessageUsed" {
    export GO_TEST_RESULT=0
    export GO_FMT_RESULT=0
    export GO_VET_RESULT=0
    export GO_MOD_VERIFY_RESULT=0
    export GO_MOD_TIDY_RESULT=0
    export GOLANGCI_LINT_EXIT_CODE=0
    export GITLEAKS_EXIT_CODE=0
    export PODMAN_INSPECT_EXISTS=0

    run_script "chore: update build scripts"

    echo "OUTPUT: $output"
    echo "ERROR: $error"

    [ "$status" -eq 0 ]
    [[ "$output" == *"git commit -m chore: update build scripts"* ]] || [[ "$error" == *"git commit -m chore: update build scripts"* ]]
}

@test "GoModVerifyFailsAborts" {
    export GO_MOD_VERIFY_RESULT=1
    run_script
    [ "$status" -ne 0 ]
    [[ "$output" == *"Go module verification failed"* ]] || [[ "$error" == *"Go module verification failed"* ]]
}

@test "GoModTidyFailsAborts" {
    export GO_MOD_TIDY_RESULT=1
    run_script
    [ "$status" -ne 0 ]
    [[ "$output" == *"go mod tidy failed"* ]] || [[ "$error" == *"go mod tidy failed"* ]]
}

@test "GitleaksImageMissingAborts" {
    export PODMAN_INSPECT_EXISTS=2  # non-zero means image not found
    run_script
    [ "$status" -ne 0 ]
    [[ "$output" == *"Gitleaks image not found"* ]] || [[ "$error" == *"Gitleaks image not found"* ]]
}


@test "GitleaksDetectsSecrets" {
    export GITLEAKS_EXIT_CODE=1
    export PODMAN_INSPECT_EXISTS=0
    run_script
    [ "$status" -ne 0 ]
    [[ "$output" == *"Gitleaks detected potential secrets"* ]] || [[ "$error" == *"Gitleaks detected potential secrets"* ]]
}

@test "AllStepsPassSuccessfully" {
    export GO_TEST_RESULT=0
    export GO_FMT_RESULT=0
    export GO_VET_RESULT=0
    export GO_MOD_VERIFY_RESULT=0
    export GO_MOD_TIDY_RESULT=0
    export GOLANGCI_LINT_EXIT_CODE=0
    export GITLEAKS_EXIT_CODE=0
    export PODMAN_INSPECT_EXISTS=0

    run_script "ci: pass pipeline"

    [ "$status" -eq 0 ]
    [[ "$output" == *"git add -A"* ]]
    [[ "$output" == *"git commit -m ci: pass pipeline"* ]] || [[ "$error" == *"git commit -m ci: pass pipeline"* ]]
    [[ "$output" == *"Successfully committed and pushed."* ]] || [[ "$error" == *"Successfully committed and pushed."* ]]
}

@test "GolangciLintFailsAborting" {
    export GOLANGCI_LINT_EXIT_CODE=1
    export GO_TEST_RESULT=0
    export GO_FMT_RESULT=0
    export GO_VET_RESULT=0
    export GO_MOD_VERIFY_RESULT=0
    export GO_MOD_TIDY_RESULT=0
    export GITLEAKS_EXIT_CODE=0
    export PODMAN_INSPECT_EXISTS=0

    run_script

    echo "OUTPUT: $output"
    echo "ERROR: $error"

    [ "$status" -eq 1 ]
    [[ "$output" == *"golangci-lint failed."* ]] || [[ "$error" == *"golangci-lint failed."* ]]
}

@test "GosecFailsAborts" {
    export GOSEC_EXIT_CODE=1
    export GO_TEST_RESULT=0
    export GO_FMT_RESULT=0
    export GO_VET_RESULT=0
    export GO_MOD_VERIFY_RESULT=0
    export GO_MOD_TIDY_RESULT=0
    export GOLANGCI_LINT_EXIT_CODE=0
    export GITLEAKS_EXIT_CODE=0
    export PODMAN_INSPECT_EXISTS=0

    run_script

    [ "$status" -ne 0 ]
    [[ "$output" == *"gosec found potential security issues."* ]] || [[ "$error" == *"gosec found potential security issues."* ]]
}

@test "GovulncheckFailsAborts" {
    export GOVULNCHECK_EXIT_CODE=1
    export GOSEC_EXIT_CODE=0
    export GO_TEST_RESULT=0
    export GO_FMT_RESULT=0
    export GO_VET_RESULT=0
    export GO_MOD_VERIFY_RESULT=0
    export GO_MOD_TIDY_RESULT=0
    export GOLANGCI_LINT_EXIT_CODE=0
    export GITLEAKS_EXIT_CODE=0
    export PODMAN_INSPECT_EXISTS=0

    run_script

    [ "$status" -ne 0 ]
    [[ "$output" == *"govulncheck reported vulnerabilities."* ]] || [[ "$error" == *"govulncheck reported vulnerabilities."* ]]
}



