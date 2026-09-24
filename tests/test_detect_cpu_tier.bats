#!/usr/bin/env bats

setup() {
  export MOCK_DIR="$(mktemp -d)"

  # Extract the function (allowing for indentation)
  awk '/^[[:space:]]*detect_cpu_tier\(\) \{/ {flag=1} flag {print} /^[[:space:]]*\}/ {if(flag) {flag=0; exit}}' ./bbr_tune.sh > "${MOCK_DIR}/detect_cpu_tier.sh"

  # To avoid modifying bash primitives like `[`, we will mock the file check by redefining the test inside the function
  # We do this by replacing the specific [ -f ... ] lines
  sed -i 's|\[ -f /lib/ld-linux-x86-64.so.2 \]|\[ "$HAS_LD_BIN" -eq 1 \]|g' "${MOCK_DIR}/detect_cpu_tier.sh"
  sed -i 's|\[ -f /lib64/ld-linux-x86-64.so.2 \]|\[ "$HAS_LD_BIN" -eq 1 \]|g' "${MOCK_DIR}/detect_cpu_tier.sh"

  # Point ld_bin to our mock instead of the real paths so it executes our mock script
  sed -i 's|ld_bin="/lib/ld-linux-x86-64.so.2"|ld_bin="'${MOCK_DIR}'/mock_ld.sh"|g; s|ld_bin="/lib64/ld-linux-x86-64.so.2"|ld_bin="'${MOCK_DIR}'/mock_ld.sh"|g' "${MOCK_DIR}/detect_cpu_tier.sh"

  cat << SCRIPT_EOF > "${MOCK_DIR}/test_env.sh"
#!/bin/bash
export LD_MOCK_V3=0
export LD_MOCK_V2=0
export CPUINFO_MOCK_V3=0
export CPUINFO_MOCK_V2=0
export HAS_LD_BIN=0

# Override grep just for cpuinfo checks
grep() {
  if [[ "\$*" == *"/proc/cpuinfo"* ]]; then
    if [[ "\$*" == *"avx2"* || "\$*" == *"bmi2"* ]]; then
      [[ "\$CPUINFO_MOCK_V3" -eq 1 ]] && return 0 || return 1
    fi
    if [[ "\$*" == *"sse4_2"* || "\$*" == *"popcnt"* ]]; then
      [[ "\$CPUINFO_MOCK_V2" -eq 1 ]] && return 0 || return 1
    fi
    return 1
  fi
  command grep "\$@"
}
export -f grep

source "${MOCK_DIR}/detect_cpu_tier.sh"
SCRIPT_EOF

  cat << 'LD_EOF' > "${MOCK_DIR}/mock_ld.sh"
#!/bin/bash
if [[ "$LD_MOCK_V3" -eq 1 ]]; then
  echo "x86-64-v3 (supported, searched)"
elif [[ "$LD_MOCK_V2" -eq 1 ]]; then
  echo "x86-64-v2 (supported, searched)"
else
  echo "x86-64-v1 (supported, searched)"
fi
LD_EOF
  chmod +x "${MOCK_DIR}/mock_ld.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "should return x64v3 when ld supports x86-64-v3" {
  run bash -c "source \"${MOCK_DIR}/test_env.sh\"; export HAS_LD_BIN=1; export LD_MOCK_V3=1; detect_cpu_tier"
  [ "$status" -eq 0 ]
  [ "$output" == "x64v3" ]
}

@test "should return x64v2 when ld supports x86-64-v2" {
  run bash -c "source \"${MOCK_DIR}/test_env.sh\"; export HAS_LD_BIN=1; export LD_MOCK_V2=1; detect_cpu_tier"
  [ "$status" -eq 0 ]
  [ "$output" == "x64v2" ]
}

@test "fallback: should return x64v3 when cpuinfo has avx2/bmi2" {
  run bash -c "source \"${MOCK_DIR}/test_env.sh\"; export HAS_LD_BIN=0; export CPUINFO_MOCK_V3=1; detect_cpu_tier"
  [ "$status" -eq 0 ]
  [ "$output" == "x64v3" ]
}

@test "fallback: should return x64v2 when cpuinfo has sse4_2/popcnt" {
  run bash -c "source \"${MOCK_DIR}/test_env.sh\"; export HAS_LD_BIN=0; export CPUINFO_MOCK_V2=1; detect_cpu_tier"
  [ "$status" -eq 0 ]
  [ "$output" == "x64v2" ]
}

@test "fallback: should return x64v1 when cpuinfo has no advanced flags" {
  run bash -c "source \"${MOCK_DIR}/test_env.sh\"; export HAS_LD_BIN=0; detect_cpu_tier"
  [ "$status" -eq 0 ]
  [ "$output" == "x64v1" ]
}
