# typed: true
# frozen_string_literal: true

# filepath: /workspaces/github/app/controllers/repos/copilot_settings/mcp_schema.rb
# app/controllers/repos/copilot_settings/mcp_schema.rb

# How to generate the MCP schema:
# 1. Run the script with `bin/rails runner script/export_mcp_schema.rb`

# 2. The schema will be saved to `ui/packages/copilot-swe-agent-settings/mcp-schema.json`

# This file defines the expected schema for MCP configuration payloads used in the Copilot SWE Agent settings.
# ----------

# Alternatively, you can use the `export_mcp_schema.rb` script to generate the schema file in the specified directory with ajv cli.
# 1 Create a working folder
# mkdir ajv-validate && cd ajv-validate

# 2 Add your updated schema as JSON
# touch mcp-schema.json
# (Paste in the updated schema content)

# 3 Run Ajv CLI to compile the validator
# npx -p ajv-cli@5.0.0 -p ajv@8.12.0 ajv compile \
#   -s mcp-schema.json \
#   -c ajv/dist/standalone \
#   -o validateMcpSchema.js

# copy the generated `validateMcpSchema.js` to ui/packages/copilot-swe-agent-settings/validateMcpSchema.js

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
                "^[a-zA-Z0-9_-]+$" => {
                  type: "object",
                  properties: {
                    command: { type: "string" },
                    type: { type: "string", enum: ["local"] },
                    args: {
                      type: "array",
                      items: { type: "string" }
                    },
                    tools: {
                      type: "array",
                      items: { type: "string" }
                    },
                    env: {
                      type: "object",
                      additionalProperties: { type: "string" }
                    }
                  },
                  required: %w[command args tools],
                  additionalProperties: false
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
