# typed: true

class AddRegistryTypeColumnToCopilotMcpAllowlists < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    unless column_exists?(:copilot_mcp_allowlists, :registry_type)
      change_table :copilot_mcp_allowlists, bulk: true do |t|
        t.column :registry_type, :integer, limit: 1, null: false, default: 0, unsigned: true, comment: "Indicates MCP Registry type: 0 = external, 1 = github"
      end
    end
  end
end
