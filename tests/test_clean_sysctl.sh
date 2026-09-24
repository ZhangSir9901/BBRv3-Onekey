#!/bin/bash
# Test script for clean_sysctl function in bbr_tune.sh

# Exit immediately if a command exits with a non-zero status.
set -e

# Setup mock sysctl.conf
export SYSCTL_CONF="$(pwd)/tests/mock_sysctl.conf"

echo "Creating mock sysctl.conf at $SYSCTL_CONF"

cat << 'MOCK' > "$SYSCTL_CONF"
# This is a dummy comment
vm.swappiness=10
net.core.default_qdisc=fq_codel
dummy.parameter=1
net.ipv4.tcp_congestion_control=reno
# Another comment
net.ipv4.ip_forward=0
keep.this.parameter=123
MOCK

# Extract the function to source it
awk '/^ *clean_sysctl\(\) *\{/{flag=1; print; next} /^ *\}/{if(flag){print; flag=0; next}} flag' ../bbr_tune.sh > tests/clean_sysctl_func.sh 2>/dev/null || \
awk '/^ *clean_sysctl\(\) *\{/{flag=1; print; next} /^ *\}/{if(flag){print; flag=0; next}} flag' bbr_tune.sh > tests/clean_sysctl_func.sh

source tests/clean_sysctl_func.sh

echo "Running clean_sysctl()"
clean_sysctl

echo "Verifying result..."
# Check that the parameters we expect to be removed are gone
if grep -q "^vm.swappiness" "$SYSCTL_CONF"; then
    echo "Test failed: vm.swappiness was not removed."
    exit 1
fi
if grep -q "^net.core.default_qdisc" "$SYSCTL_CONF"; then
    echo "Test failed: net.core.default_qdisc was not removed."
    exit 1
fi
if grep -q "^net.ipv4.tcp_congestion_control" "$SYSCTL_CONF"; then
    echo "Test failed: net.ipv4.tcp_congestion_control was not removed."
    exit 1
fi
if grep -q "^net.ipv4.ip_forward" "$SYSCTL_CONF"; then
    echo "Test failed: net.ipv4.ip_forward was not removed."
    exit 1
fi

# Check that dummy parameters and comments are retained
if ! grep -q "^dummy.parameter=1" "$SYSCTL_CONF"; then
    echo "Test failed: dummy.parameter was removed."
    exit 1
fi
if ! grep -q "^keep.this.parameter=123" "$SYSCTL_CONF"; then
    echo "Test failed: keep.this.parameter was removed."
    exit 1
fi
if ! grep -q "^# This is a dummy comment" "$SYSCTL_CONF"; then
    echo "Test failed: comment was removed."
    exit 1
fi

echo "All tests passed successfully!"

# Cleanup
rm -f "$SYSCTL_CONF" tests/clean_sysctl_func.sh
