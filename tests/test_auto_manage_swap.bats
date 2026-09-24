#!/usr/bin/env bats

setup() {
  TEST_SCRIPT=$(mktemp)
  export MOCK_FSTAB=$(mktemp)
  export MOCK_LOG=$(mktemp)

  # Determine correct path to bbr_tune.sh relative to the bats execution directory
  # When running `bats tests/test_auto_manage_swap.bats`, PWD is repo root
  BBR_SCRIPT="bbr_tune.sh"
  if [ ! -f "$BBR_SCRIPT" ]; then
    BBR_SCRIPT="../bbr_tune.sh"
  fi

  cat << 'SCRIPT_EOF' > "$TEST_SCRIPT"
YELLOW='\033[1;33m'
PLAIN='\033[0m'
GREEN='\033[32m'
SCRIPT_EOF

  # Extract the function and replace /etc/fstab with our mock file
  sed -n '/auto_manage_swap() {/,/^}/p' "$BBR_SCRIPT" | sed "s|/etc/fstab|$MOCK_FSTAB|g" >> "$TEST_SCRIPT"

  source "$TEST_SCRIPT"
}

teardown() {
  rm -f "$TEST_SCRIPT"
  rm -f "$MOCK_FSTAB"
  rm -f "$MOCK_LOG"
}

# Helper to mock free command
mock_free() {
  local mem_val=$1
  local swap_val=$2
  eval "
  free() {
    echo '              total        used        free      shared  buff/cache   available'
    echo 'Mem:           $mem_val         500         524           0           0         524'
    echo 'Swap:           $swap_val           0         256'
  }
  export -f free
  "
}

# Helper to mock grep command
mock_grep() {
  local exit_code=$1
  eval "
  grep() {
    return $exit_code
  }
  export -f grep
  "
}

# Generic mock for destructive commands
mock_commands() {
  eval "
  fallocate() { echo 'fallocate called' >> \"\$MOCK_LOG\"; }
  dd() { echo 'dd called' >> \"\$MOCK_LOG\"; }
  chmod() { echo 'chmod called' >> \"\$MOCK_LOG\"; }
  mkswap() { echo 'mkswap called' >> \"\$MOCK_LOG\"; }
  swapon() { echo 'swapon called' >> \"\$MOCK_LOG\"; }
  export -f fallocate dd chmod mkswap swapon
  "
}

@test "auto_manage_swap triggers when RAM is small and Swap is small" {
  mock_free 1024 256
  mock_grep 1
  mock_commands

  run auto_manage_swap

  # Check output
  [[ "$output" == *"[内存急救] 检测到本机物理内存较小 (1024MB) "* ]]
  [[ "$output" == *"[成功] 1GB Swap 兜底气囊创建完毕！"* ]]

  # Check if commands were called
  run cat "$MOCK_LOG"
  [[ "$output" == *"fallocate called"* ]]
  [[ "$output" == *"chmod called"* ]]
  [[ "$output" == *"mkswap called"* ]]
  [[ "$output" == *"swapon called"* ]]

  # Check if fstab was modified
  run cat "$MOCK_FSTAB"
  [[ "$output" == *"/swapfile swap swap defaults 0 0"* ]]
}

@test "auto_manage_swap does NOT trigger when RAM is > 1536" {
  mock_free 2048 256
  mock_grep 1
  mock_commands

  run auto_manage_swap

  [[ "$output" == "" ]]
  run cat "$MOCK_LOG"
  [[ "$output" == "" ]]
}

@test "auto_manage_swap does NOT trigger when Swap is >= 512" {
  mock_free 1024 1024
  mock_grep 1
  mock_commands

  run auto_manage_swap

  [[ "$output" == "" ]]
  run cat "$MOCK_LOG"
  [[ "$output" == "" ]]
}

@test "auto_manage_swap skips swap creation if /etc/fstab already has swapfile" {
  mock_free 1024 256
  mock_grep 0 # Means grep found /swapfile
  mock_commands

  run auto_manage_swap

  [[ "$output" == *"[内存急救]"* ]]
  [[ "$output" != *"[成功]"* ]]
  run cat "$MOCK_LOG"
  [[ "$output" == "" ]]
}

@test "auto_manage_swap falls back to dd if fallocate fails" {
  mock_free 1024 256
  mock_grep 1

  eval "
  fallocate() { echo 'fallocate called' >> \"\$MOCK_LOG\"; return 1; }
  dd() { echo 'dd called' >> \"\$MOCK_LOG\"; }
  chmod() { echo 'chmod called' >> \"\$MOCK_LOG\"; }
  mkswap() { echo 'mkswap called' >> \"\$MOCK_LOG\"; }
  swapon() { echo 'swapon called' >> \"\$MOCK_LOG\"; }
  export -f fallocate dd chmod mkswap swapon
  "

  run auto_manage_swap

  [[ "$output" == *"[内存急救]"* ]]

  run cat "$MOCK_LOG"
  [[ "$output" == *"fallocate called"* ]]
  [[ "$output" == *"dd called"* ]]
  [[ "$output" == *"chmod called"* ]]
}

@test "auto_manage_swap handles missing Mem line" {
  eval "
  free() {
    echo '              total        used        free      shared  buff/cache   available'
    echo 'Swap:           256           0         256'
  }
  export -f free
  "
  mock_grep 1
  mock_commands

  run auto_manage_swap

  # The output will contain "integer expression expected" error because total_ram_mb is empty
  [[ "$output" == *"integer expression expected"* ]]
}

@test "auto_manage_swap handles missing Swap line" {
  eval "
  free() {
    echo '              total        used        free      shared  buff/cache   available'
    echo 'Mem:           1024         500         524           0           0         524'
  }
  export -f free
  "
  mock_grep 1
  mock_commands

  run auto_manage_swap

  # The output will contain "integer expression expected" error because current_swap_mb is empty
  [[ "$output" == *"integer expression expected"* ]]
}
