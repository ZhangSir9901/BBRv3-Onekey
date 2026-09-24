#!/bin/bash

# Setup environment
HAS_IPV4="true"
HAS_IPV6="false"

# Mock curl to return nothing or failure
curl() {
    # Simulate API failure
    return 1
}

# Extract the get_country_code function from bbr_tune.sh
sed -n '/^get_country_code() {/,/^}/p' bbr_tune.sh > temp_func.sh

# Source the function
source temp_func.sh

# Run the function
RESULT=$(get_country_code)

if [ "$RESULT" = "US" ]; then
    echo "Test passed: Fallback to US when curl fails"
    rm temp_func.sh
    exit 0
else
    echo "Test failed: Expected US, got $RESULT"
    rm temp_func.sh
    exit 1
fi
