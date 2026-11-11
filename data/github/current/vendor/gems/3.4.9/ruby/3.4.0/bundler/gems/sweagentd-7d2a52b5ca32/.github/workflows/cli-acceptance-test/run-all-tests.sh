#!/bin/bash

# CLI Acceptance Test Runner
# This script runs all CLI acceptance tests in the current directory.
# It's excluded from being run as a test itself.

set -euo pipefail

echo "🧪 Running all CLI acceptance tests..."

test_dir="$(dirname "$0")"
failed_tests=()
total_tests=0

# Find all .sh files in the test directory, excluding this runner script
for test_script in "$test_dir"/*.sh; do
  if [ -f "$test_script" ]; then
    test_name=$(basename "$test_script" .sh)
    
    # Skip the test runner script itself
    if [ "$test_name" = "run-all-tests" ]; then
      continue
    fi
    
    total_tests=$((total_tests + 1))
    
    echo ""
    echo "🚀 Running test: $test_name"
    echo "=================================="
    
    # Run the test script, capture exit code but don't fail immediately
    if "$test_script"; then
      echo "✅ $test_name: PASSED"
    else
      echo "❌ $test_name: FAILED"
      failed_tests+=("$test_name")
    fi
  fi
done

echo ""
echo "📊 Test Results Summary"
echo "======================="
echo "Total tests: $total_tests"
echo "Passed: $((total_tests - ${#failed_tests[@]}))"
echo "Failed: ${#failed_tests[@]}"

if [ ${#failed_tests[@]} -gt 0 ]; then
  echo ""
  echo "❌ Failed tests:"
  for failed_test in "${failed_tests[@]}"; do
    echo "  - $failed_test"
  done
  exit 1
else
  echo ""
  echo "🎉 All tests passed!"
fi