# frozen_string_literal: true

#!/usr/bin/env ruby
# This script must be run with Rails runner: bin/rails runner script/export_mcp_schema.rb
# filepath: /workspaces/github/script/export_mcp_schema.rb
# script/export_mcp_schema.rb
require_relative "../app/controllers/repos/copilot_settings/mcp_schema"
require "json"

schema = Repos::CopilotSettings::McpSchema::MCPPayload::EXPECTED_MCP_CONFIGURATION_SCHEMA

# Create the directory if it doesn't exist
output_dir = File.join(Rails.root, "ui/packages/copilot-swe-agent-settings")
Dir.mkdir(output_dir) unless Dir.exist?(output_dir)

# Write the schema to a file that both Ruby and JavaScript can access
output_file = File.join(output_dir, "mcp-schema.json")
File.write(output_file, JSON.pretty_generate(schema))

puts "Schema exported to #{output_file}"
