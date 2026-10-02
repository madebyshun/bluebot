#!/usr/bin/env bash
# Amount math, ABI encoding, and the SIWE message BlueBot signs — which must be
# byte-for-byte the server's (apps/web src/lib/siwe-session-message.ts).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bluebot-evm.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc Sources/App/EVM.swift tests/EVMTests.swift -o "$TEST_DIR/evm-tests"
"$TEST_DIR/evm-tests" > "$TEST_DIR/swift-siwe.txt"
EXPECTED="$(dirname "$0")/../tests/siwe-expected.txt"
if ! diff -q "$TEST_DIR/swift-siwe.txt" "$EXPECTED" >/dev/null; then
  echo "SIWE message drifted from the server's:"; diff "$TEST_DIR/swift-siwe.txt" "$EXPECTED"; exit 1
fi
echo "EVM math, ABI and SIWE message: all cases passed"
