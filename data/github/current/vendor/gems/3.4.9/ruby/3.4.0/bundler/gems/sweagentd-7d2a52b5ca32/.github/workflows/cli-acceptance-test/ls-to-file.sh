#!/bin/bash
set -euo pipefail

# Run "ls and check" acceptance test
echo "🧪 Running ls and check test..."

# Cleanup function to ensure test debris is removed
cleanup() {
  echo "🧹 Cleaning up test files..."
  rm -f test-file.txt
}

# Set trap to cleanup on exit (success or failure)
trap cleanup EXIT

copilot \
  -p "Run the ls command to list files in the current directory and use the write tool to put the listing in a file in the current directory called test-file.txt" \
  --allow-all-tools \
  --allow-all-paths

if [ -f test-file.txt ]; then
  cat test-file.txt
  echo "✅ Acceptance test passed"
else
  echo "❌ Acceptance test failed"
  exit 1
fi