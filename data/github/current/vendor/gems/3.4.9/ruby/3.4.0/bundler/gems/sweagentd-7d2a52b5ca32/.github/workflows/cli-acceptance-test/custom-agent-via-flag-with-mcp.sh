#!/bin/bash
set -euo pipefail

# Run "custom agent" acceptance test
echo "🧪 Running custom agent test..."

# Cleanup function to ensure test debris is removed
cleanup() {
  echo "🧹 Cleaning up test files..."
  rm -f mcp-server
  rm -f mcp-server.exe
  rm -f .github/agents/test-file-writer.md
  rm -f test-file.txt
  # Only remove the agents directory if it's empty and we created it
  if [ -d .github/agents ] && [ -z "$(ls -A .github/agents 2>/dev/null)" ]; then
    rmdir .github/agents 2>/dev/null || true
  fi
}

# Set trap to cleanup on exit (success or failure)
trap cleanup EXIT

# Build the MCP server tool binary
echo "🔧 Building MCP server tool binary..."
# Determine the executable name based on OS
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
  MCP_SERVER_BINARY="mcp-server.exe"
else
  MCP_SERVER_BINARY="mcp-server"
fi
go -C .github/workflows/cli-acceptance-test/test-mcp-server build -o "../../../../$MCP_SERVER_BINARY"

# Ensure the agents directory exists
mkdir -p .github/agents

# Create a custom agent definition file for this test
cat > .github/agents/test-file-writer.md << EOF
---
name: test-file-writer
description: Creates "test-file.txt" file
mcp-servers:
  create-file:
    command: ./$MCP_SERVER_BINARY
    args: []
    tools: ["*"]
---

When invoked:
 * You use the "create_file" MCP server tool to create a file in the current working directory called "test-file.txt"
EOF

# Run the CLI with the custom agent
echo "🚀 Testing copilot using test-file-writer custom agent as a tool with MCP server"
CUSTOM_AGENTS=true copilot \
  -p "create the file" \
  --agent "test-file-writer" \
  --allow-tool 'create-file'

# Validate the output
if [ -f test-file.txt ]; then
  cat test-file.txt
  echo "✅ Acceptance test passed"
else
  echo "❌ Acceptance test failed"
  exit 1
fi