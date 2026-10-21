# shellcheck shell=bash disable=SC2034 # TEST_FAILED is read by tests/run.sh
# Assertions for tests/*.test.sh. A failed assertion prints why and marks the test failed;
# the test function keeps running so every failure is reported.

assert_eq() { # <expected> <actual> <msg>
    [ "$1" = "$2" ] && return 0
    echo "    FAIL: $3: expected '$1', got '$2'"
    TEST_FAILED=1
    return 1
}

assert_ok() { # <msg> <cmd...>
    local msg=$1; shift
    "$@" >/dev/null 2>&1 && return 0
    echo "    FAIL: $msg: command failed: $*"
    TEST_FAILED=1
    return 1
}

assert_fails() { # <msg> <cmd...>
    local msg=$1 status; shift
    "$@" >/dev/null 2>&1
    status=$?
    # 126/127: the command could not run at all, which is not a rejection
    if [ "$status" -ne 0 ] && [ "$status" -ne 126 ] && [ "$status" -ne 127 ]; then return 0; fi
    echo "    FAIL: $msg: expected a rejection, got exit $status: $*"
    TEST_FAILED=1
    return 1
}
