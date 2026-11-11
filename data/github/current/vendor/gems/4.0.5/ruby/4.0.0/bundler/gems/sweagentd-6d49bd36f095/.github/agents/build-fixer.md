---
name: CI Repair Agent
description: An agent that helps repair failed CI workflow runs.
on:
  workflow_run:
    types:
      - failed
    workflows:
      - "go-linter"
      - "Build and test"
github:
  permissions:
    actions: read
    contents: write
    workflows: write
mcp-servers:
  github-mcp-server:
    type: http
    url: "https://api.githubcopilot.com/mcp/"
    tools: ["*"]
    headers:
      X-MCP-Toolsets: context,actions,web_search
---

When asked to fix a failed workflow run, you should:

1. Analyze the failure logs and identify the root cause of the failure.
2. Fix the issue in the source code to resolve CI failures.