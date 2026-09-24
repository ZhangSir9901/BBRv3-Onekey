#!/bin/bash

# Dynamically extract retry_command from bbr_tune.sh
eval "$(sed -n '/^[[:space:]]*retry_command() {/,/^[[:space:]]*}/p' bbr_tune.sh)"

# Define colors used by retry_command to avoid unbound variable errors or messy output
RED='\033[31m'
YELLOW='\033[1;33m'
PLAIN='\033[0m'

# Mock sleep to avoid waiting during tests
sleep() {
    return 0
}

# Test state
TEST_FAILURES=0
MOCK_CALL_COUNT=0

# A mock command that always succeeds
mock_success() {
    ((MOCK_CALL_COUNT++))
    return 0
}

# A mock command that always fails
mock_fail() {
    ((MOCK_CALL_COUNT++))
    return 1
}

# A mock command that fails N times then succeeds
FAILS_LEFT=0
mock_fail_n_times() {
    ((MOCK_CALL_COUNT++))
    if (( FAILS_LEFT > 0 )); then
        ((FAILS_LEFT--))
        return 1
    fi
    return 0
}

assert_eq() {
    local expected=$1
    local actual=$2
    local msg=$3
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $msg (Expected: $expected, Actual: $actual)"
        ((TEST_FAILURES++))
    else
        echo "PASS: $msg"
    fi
}

echo "Running tests for retry_command..."

# Test 1: Immediate success
MOCK_CALL_COUNT=0
# redirecting output to /dev/null so test output is cleaner,
# but capturing return code.
retry_command mock_success >/dev/null
assert_eq 0 $? "Immediate success should return 0"
assert_eq 1 $MOCK_CALL_COUNT "mock_success should be called exactly once"

# Test 2: Fails 3 times, succeeds on 4th attempt
MOCK_CALL_COUNT=0
FAILS_LEFT=3
retry_command mock_fail_n_times >/dev/null
assert_eq 0 $? "Eventual success should return 0"
assert_eq 4 $MOCK_CALL_COUNT "mock_fail_n_times should be called 4 times"

# Test 3: Fails 5 times (max attempts)
MOCK_CALL_COUNT=0
retry_command mock_fail >/dev/null
assert_eq 1 $? "Max failures should return 1"
assert_eq 5 $MOCK_CALL_COUNT "mock_fail should be called 5 times (max attempts)"

# Summary
if (( TEST_FAILURES > 0 )); then
    echo "Tests failed: $TEST_FAILURES"
    exit 1
else
    echo "All tests passed!"
    exit 0
fi
