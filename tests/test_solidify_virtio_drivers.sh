#!/bin/bash

# Stop on error
set -e

echo "Starting tests for solidify_virtio_drivers..."

# Extract the function from bbr_tune.sh
awk '/^solidify_virtio_drivers\(\) \{/{flag=1} flag; /^\}/{if(flag) {flag=0; print ""; next}}' ./bbr_tune.sh > /tmp/func.sh
source /tmp/func.sh

# Temporary directory for tests
TEST_DIR=$(mktemp -d)
export INITRAMFS_MODULES_FILE="$TEST_DIR/modules"
FAIL=0

# Test 1: Happy Path (Empty File)
touch "$INITRAMFS_MODULES_FILE"
solidify_virtio_drivers

expected="virtio
virtio_pci
virtio_net
virtio_blk
virtio_scsi
virtio_ring"

actual=$(cat "$INITRAMFS_MODULES_FILE")

if [ "$actual" = "$expected" ]; then
    echo "✅ Test 1 (Empty File): Passed"
else
    echo "❌ Test 1 (Empty File): Failed"
    echo "Expected:"
    echo "$expected"
    echo "Actual:"
    echo "$actual"
    FAIL=1
fi

# Test 2: Edge Case (Partial Content)
echo "virtio" > "$INITRAMFS_MODULES_FILE"
echo "virtio_net" >> "$INITRAMFS_MODULES_FILE"
solidify_virtio_drivers

actual=$(cat "$INITRAMFS_MODULES_FILE")

expected="virtio
virtio_net
virtio_pci
virtio_blk
virtio_scsi
virtio_ring"

if [ "$actual" = "$expected" ]; then
    echo "✅ Test 2 (Partial Content): Passed"
else
    echo "❌ Test 2 (Partial Content): Failed"
    echo "Expected:"
    echo "$expected"
    echo "Actual:"
    echo "$actual"
    FAIL=1
fi

# Test 3: Error Condition (File Missing)
rm -f "$INITRAMFS_MODULES_FILE"
solidify_virtio_drivers

if [ ! -f "$INITRAMFS_MODULES_FILE" ]; then
    echo "✅ Test 3 (File Missing): Passed"
else
    echo "❌ Test 3 (File Missing): Failed"
    echo "File was created unexpectedly."
    FAIL=1
fi

# Cleanup
rm -rf "$TEST_DIR"
rm -f /tmp/func.sh

if [ "$FAIL" -ne 0 ]; then
    echo "❌ Some tests failed!"
    exit 1
fi

echo "🎉 All tests passed successfully!"
