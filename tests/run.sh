#!/usr/bin/env bash
# Runs every test_* function in tests/*.test.sh, each in its own subshell from the repo root.
# Each test gets $A and $B (fresh copies of tests/fixtures/Dockerfile.pin) and $SHA.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

# shellcheck disable=SC2034 # used by the sourced tests
SHA=08bc2eba2a588654ade1357174aa646b761556c862dda0678345ee29ed481209
total=0
failed=0
for file in tests/*.test.sh; do
    tests=$(bash -c 'source tests/lib.sh; source "$1"; declare -F' _ "$file" | awk '$3 ~ /^test_/ { print $3 }')
    for t in $tests; do
        total=$((total + 1))
        if (
            TEST_FAILED=0
            tmp=$(mktemp -d)
            trap 'rm -rf "$tmp"' EXIT
            A=$tmp/A.Dockerfile
            B=$tmp/B.Dockerfile
            cp tests/fixtures/Dockerfile.pin "$A"
            cp tests/fixtures/Dockerfile.pin "$B"
            source tests/lib.sh
            # shellcheck source=/dev/null
            source "$file"
            "$t"
            exit "$TEST_FAILED"
        ); then
            echo "ok   $t"
        else
            echo "FAIL $t"
            failed=$((failed + 1))
        fi
    done
done

echo "$((total - failed))/$total passed"
[ "$failed" -eq 0 ] && [ "$total" -gt 0 ]
