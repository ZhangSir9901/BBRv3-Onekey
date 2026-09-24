#!/bin/bash

# Extract get_country_code function from bbr_tune.sh
eval "$(awk '/^[[:space:]]*get_country_code\(\)[[:space:]]*\{/{flag=1} flag; /^[[:space:]]*\}/{if(flag){flag=0; exit}}' bbr_tune.sh)"

# Setup temporary directory for state
TEST_TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMP_DIR"' EXIT

CURL_FLAG_FILE="$TEST_TMP_DIR/curl_flag_used"
CURL_CF_FILE="$TEST_TMP_DIR/curl_called_cf"
CURL_IPINFO_FILE="$TEST_TMP_DIR/curl_called_ipinfo"

# Mock curl function - redefine curl completely
curl() {
    # We must write variables to a temporary file since subshells can't modify globals
    if [[ "$*" == *"-6"* ]]; then
        echo "1" > "$CURL_FLAG_FILE"
    fi

    if [[ "$*" == *"cloudflare.com"* ]]; then
        echo "1" > "$CURL_CF_FILE"
        if [ "$MOCK_CF_RESPONSE" = "XX" ]; then
            echo "loc=XX"
        elif [ "$MOCK_CF_RESPONSE" = "FAIL" ]; then
            return 1
        elif [ -n "$MOCK_CF_RESPONSE" ]; then
            echo "loc=$MOCK_CF_RESPONSE"
        fi
    elif [[ "$*" == *"ipinfo.io"* ]]; then
        echo "1" > "$CURL_IPINFO_FILE"
        if [ "$MOCK_IPINFO_RESPONSE" = "FAIL" ]; then
            return 1
        elif [ -n "$MOCK_IPINFO_RESPONSE" ]; then
            echo -n "$MOCK_IPINFO_RESPONSE"
        fi
    fi
}

# Export functions and vars
export -f curl
export -f get_country_code
export CURL_FLAG_FILE CURL_CF_FILE CURL_IPINFO_FILE

# Test Runner
test_cases=0
test_failures=0

run_test() {
    local name="$1"
    local expected="$2"
    local setup_func="$3"
    local check_func="$4"

    echo "Running test: $name"

    # Reset state
    export HAS_IPV4="true"
    export HAS_IPV6="false"
    export MOCK_CF_RESPONSE=""
    export MOCK_IPINFO_RESPONSE=""

    echo "0" > "$CURL_FLAG_FILE"
    echo "0" > "$CURL_CF_FILE"
    echo "0" > "$CURL_IPINFO_FILE"

    # Run setup
    if [ -n "$setup_func" ]; then
        eval "$setup_func"
    fi

    # Run function
    local result=$(get_country_code)

    # Verify result
    if [ "$result" != "$expected" ]; then
        echo "  ❌ FAILED: Expected '$expected', got '$result'"
        test_failures=$((test_failures + 1))
    else
        # Run additional checks
        if [ -n "$check_func" ]; then
            if ! eval "$check_func"; then
                echo "  ❌ FAILED: Custom check failed"
                test_failures=$((test_failures + 1))
            else
                echo "  ✅ PASSED"
            fi
        else
            echo "  ✅ PASSED"
        fi
    fi

    test_cases=$((test_cases + 1))
}

# Test Scenarios

# 1. Primary API Success
setup_cf_success() {
    export MOCK_CF_RESPONSE="FR"
}
check_cf_only() {
    [ "$(cat "$CURL_CF_FILE")" = "1" ] && [ "$(cat "$CURL_IPINFO_FILE")" = "0" ]
}
run_test "Primary API Success (Cloudflare)" "FR" "setup_cf_success" "check_cf_only"

# 2. Primary API 'XX' Fallback
setup_cf_xx() {
    export MOCK_CF_RESPONSE="XX"
    export MOCK_IPINFO_RESPONSE="DE"
}
check_both_called() {
    [ "$(cat "$CURL_CF_FILE")" = "1" ] && [ "$(cat "$CURL_IPINFO_FILE")" = "1" ]
}
run_test "Primary API 'XX' Fallback to IPInfo" "DE" "setup_cf_xx" "check_both_called"

# 3. Primary API Failure
setup_cf_fail() {
    export MOCK_CF_RESPONSE="FAIL"
    export MOCK_IPINFO_RESPONSE="GB"
}
run_test "Primary API Failure Fallback to IPInfo" "GB" "setup_cf_fail" "check_both_called"

# 4. Complete API Failure
setup_all_fail() {
    export MOCK_CF_RESPONSE="FAIL"
    export MOCK_IPINFO_RESPONSE="FAIL"
}
run_test "Complete API Failure Fallback to Default (US)" "US" "setup_all_fail" "check_both_called"

# 5. IPv6 Mode
setup_ipv6_mode() {
    export HAS_IPV4="false"
    export HAS_IPV6="true"
    export MOCK_CF_RESPONSE="JP"
}
check_ipv6_flag() {
    [ "$(cat "$CURL_FLAG_FILE")" = "1" ]
}
run_test "IPv6 Only Mode adds -6 flag" "JP" "setup_ipv6_mode" "check_ipv6_flag"


echo ""
echo "Test Summary:"
echo "Total tests: $test_cases"
if [ $test_failures -eq 0 ]; then
    echo "Result: All tests passed! 🎉"
    exit 0
else
    echo "Result: $test_failures test(s) failed. ❌"
    exit 1
fi
