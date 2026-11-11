# typed: true
# frozen_string_literal: true

# filepath: /workspaces/github/app/controllers/repos/copilot_settings/mcp_schema.rb
# app/controllers/repos/copilot_settings/mcp_schema.rb

# How to generate the MCP schema:
# 1. Run the script with `bin/rails runner script/export_mcp_schema.rb`
#
# 2. The schema will be saved to `ui/packages/copilot-swe-agent-settings/mcp-schema.json`
#
# You will then need to submit a PR to the github-ui repo to update the schema file in this
# same location, and manually update `validateMcpSchema.js` with any updates.

module Repos
  module CopilotSettings
    module McpSchema
      module MCPPayload
        EXPECTED_MCP_CONFIGURATION_SCHEMA = {
          type: "object",
          properties: {
            mcpServers: {
              type: "object",
              patternProperties: {
                "^[a-zA-Z0-9/_-]+$" => {
                  type: "object",
                  properties: {
                    type: { type: "string", enum: %w[local stdio http sse] },
                    command: { type: "string" },
                    args: { type: "array", items: { type: "string" } },
                    tools: { type: "array", items: { type: "string" } },
                    env: { type: "object", additionalProperties: { type: "string" } },
                    cwd: { type: "string" },
                    url: { type: "string" },
                    headers: { type: "object", additionalProperties: { type: "string" } }
                  },
                  required: %w[type tools],
                  # Use oneOf instead of allOf with if/then/else
                  oneOf: [
                    {
                      # Local server schema
                      properties: {
                        type: { const: "local" }
                      },
                      required: %w[type tools command args],
                      not: {
                        anyOf: [
                          { required: ["url"] },
                          { required: ["headers"] }
                        ]
                      }
                    },
                    {
                      # stdio server schema
                      properties: {
                        type: { const: "stdio" }
                      },
                      required: %w[type tools command args],
                      not: {
                        anyOf: [
                          { required: ["url"] },
                          { required: ["headers"] }
                        ]
                      }
                    },
                    {
                      # HTTP server schema
                      properties: {
                        type: { const: "http" }
                      },
                      required: %w[type tools url],
                      not: {
                        anyOf: [
                          { required: ["command"] },
                          { required: ["args"] },
                          { required: ["env"] },
                          { required: ["cwd"] }
                        ]
                      }
                    },
                    {
                      # SSE server schema
                      properties: {
                        type: { const: "sse" }
                      },
                      required: %w[type tools url],
                      not: {
                        anyOf: [
                          { required: ["command"] },
                          { required: ["args"] },
                          { required: ["env"] },
                          { required: ["cwd"] }
                        ]
                      }
                    }
                  ],
                  additionalProperties: false
                }
              },
              additionalProperties: false
            },
            github: {
              type: "object",
              description: "GitHub-specific configurations for the agent.",
              properties: {
                permissions: {
                  description: "GitHub token permissions for the agent.",
                  oneOf: [
                    {
                      type: "string",
                      description: "Shorthand to set the highest allowed permission level for each scope, subject to per-scope restrictions.",
                      enum: %w[read-all write-all]
                    },
                    {
                      type: "object",
                      description: "Per-scope permission levels.",
                      properties: {
                        actions: {
                          type: "string",
                          description: "Access to GitHub Actions workflows, runs, and artifacts.",
                          enum: %w[read write none]
                        },
                        checks: {
                          type: "string",
                          description: "Access to check runs and check suites.",
                          enum: %w[read none]
                        },
                        contents: {
                          type: "string",
                          description: "Access to repository contents, commits, branches, and merges.",
                          enum: %w[read write none]
                        },
                        discussions: {
                          type: "string",
                          description: "Access to discussions and related comments and labels.",
                          enum: %w[read write none]
                        },
                        issues: {
                          type: "string",
                          description: "Access to issues and related comments, assignees, labels, and milestones.",
                          enum: %w[read write none]
                        },
                        metadata: {
                          type: "string",
                          description: "Repository metadata (always read-only).",
                          enum: %w[read]
                        },
                        "pull-requests": {
                          type: "string",
                          description: "Access to pull requests and related comments, assignees, labels, and milestones.",
                          enum: %w[read write none]
                        },
                        "security-events": {
                          type: "string",
                          description: "Access to code scanning and Dependabot alerts.",
                          enum: %w[read none]
                        },
                        workflows: {
                          type: "string",
                          description: "Access to modify workflow files.",
                          enum: %w[write none]
                        }
                      },
                      additionalProperties: false
                    }
                  ]
                }
              },
              additionalProperties: false
            }
          },
          additionalProperties: false
        }.freeze
      end
    end
  end
end
