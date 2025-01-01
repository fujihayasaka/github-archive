# typed: true
# frozen_string_literal: true

class RenameMcpEnabledColumnInCopilotConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    change_table :copilot_configurations, bulk: true do |t|
      t.column :mcp, :integer, limit: 1, null: false, default: 0, comment: "Policy for Copilot MCP server usage"
      t.remove :mcp_enabled
    end
  end

  def down
    change_table :copilot_configurations, bulk: true do |t|
      t.column :mcp_enabled, :integer, limit: 1, null: false, default: 0, comment: "The policy for allowing MCP servers to be configured for an enterprise"
      t.remove :mcp
    end
  end
end
