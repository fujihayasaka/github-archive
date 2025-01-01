# typed: true
# frozen_string_literal: true

class AddMcpEnabledToCopilotConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :mcp_enabled, :integer, limit: 1, null: false, default: 0, comment: "The policy for allowing MCP servers to be configured for an enterprise"
    end
  end
end
