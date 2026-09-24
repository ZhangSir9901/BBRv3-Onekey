#!/usr/bin/env bats

setup() {
  # Source the main script. The script is now wrapped in a BASH_SOURCE[0] guard,
  # so top-level commands won't execute when sourced, but variables and functions will be available.
  # We need to source it using absolute path or relative to BATS_TEST_DIRNAME
  source "${BATS_TEST_DIRNAME}/bbr_tune.sh"

  # Ensure the variables used by functions are exported if not already
  export PLAIN='\033[0m'
  export RED='\033[31m'
  export YELLOW='\033[1;33m'
  export GREEN='\033[32m'
}

# --- retry_command tests ---
@test "retry_command succeeds on first try" {
  run retry_command true
  [ "$status" -eq 0 ]
}

@test "retry_command fails after max attempts" {
  run retry_command false
  [ "$status" -eq 1 ]
  [[ "$output" == *"[错误]"* ]]
}

# --- get_country_code tests ---
@test "get_country_code returns country from first url" {
  curl() {
    if [[ "$*" == *"cloudflare.com"* ]]; then
      echo "loc=FR"
    else
      echo "US"
    fi
  }
  export -f curl

  export HAS_IPV4="true"
  export HAS_IPV6="true"

  run get_country_code
  [ "$status" -eq 0 ]
  [ "$output" = "FR" ]
}

@test "get_country_code falls back to second url" {
  curl() {
    if [[ "$*" == *"cloudflare.com"* ]]; then
      echo "loc=XX"
    elif [[ "$*" == *"ipinfo.io"* ]]; then
      echo "DE"
    else
      echo "US"
    fi
  }
  export -f curl

  export HAS_IPV4="true"
  export HAS_IPV6="true"

  run get_country_code
  [ "$status" -eq 0 ]
  [ "$output" = "DE" ]
}

@test "get_country_code falls back to US on failure" {
  curl() {
    echo ""
  }
  export -f curl

  export HAS_IPV4="true"
  export HAS_IPV6="true"

  run get_country_code
  [ "$status" -eq 0 ]
  [ "$output" = "US" ]
}

# --- detect_cpu_tier tests ---
@test "detect_cpu_tier detects x64v3 from ld output" {

  # Bash doesn't allow exporting functions with slashes easily.
  # A better way is to dynamically replace the hardcoded path in the function definition
  # before executing it to point to a mock we control, while preserving the actual logic.
  eval "$(declare -f detect_cpu_tier | sed 's|/lib/ld-linux-x86-64.so.2|mock_ld|g' | sed 's|/lib64/ld-linux-x86-64.so.2|mock_ld|g')"

  mock_ld() {
    echo "x86-64-v3 (supported, searched)"
  }
  export -f mock_ld

  run detect_cpu_tier
  [ "$status" -eq 0 ]
  [ "$output" = "x64v3" ]

  unset -f mock_ld
}

@test "detect_cpu_tier falls back to grep /proc/cpuinfo for x64v2" {
  # Mock grep to simulate x64v2 features
  grep() {
    if [[ "$*" == *"avx2"* ]]; then
      return 1 # Not found
    elif [[ "$*" == *"sse4_2"* ]] || [[ "$*" == *"popcnt"* ]]; then
      return 0 # Found
    fi
    # Default grep behavior
    command grep "$@"
  }
  export -f grep

  # We dynamically replace the check `[ -f ... ]` in the function definition
  # to make it look like the ld binary is missing so it falls back to grep
  eval "$(declare -f detect_cpu_tier | sed 's|\[ -f /lib|false \&\& \[ -f /lib|g' | sed 's|\[ -f /lib64|false \&\& \[ -f /lib64|g')"

  run detect_cpu_tier
  [ "$status" -eq 0 ]
  [ "$output" = "x64v2" ]

  unset -f grep
}

# --- auto_manage_swap tests ---
@test "auto_manage_swap triggers on low ram and low swap" {
  # Mock free to simulate low memory and no swap
  free() {
    if [[ "$*" == *"-m"* ]]; then
      echo "              total        used        free      shared  buff/cache   available"
      echo "Mem:           1024         500         200          50         324         400"
      echo "Swap:             0           0           0"
    else
      command free "$@"
    fi
  }
  export -f free

  # Mock fallocate, dd, chmod, mkswap, swapon to do nothing
  fallocate() { true; }
  export -f fallocate
  dd() { true; }
  export -f dd
  chmod() { true; }
  export -f chmod
  mkswap() { true; }
  export -f mkswap
  swapon() { true; }
  export -f swapon

  # Mock grep to return false (not found in /etc/fstab)
  grep() { return 1; }
  export -f grep

  run auto_manage_swap
  [ "$status" -eq 0 ]
  [[ "$output" == *"[内存急救]"* ]]
  [[ "$output" == *"[成功]"* ]]
}

@test "auto_manage_swap does not trigger on high ram" {
  # Mock free to simulate high memory
  free() {
    if [[ "$*" == *"-m"* ]]; then
      echo "              total        used        free      shared  buff/cache   available"
      echo "Mem:           4096         500        3000          50         546        3400"
      echo "Swap:             0           0           0"
    else
      command free "$@"
    fi
  }
  export -f free

  run auto_manage_swap
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
