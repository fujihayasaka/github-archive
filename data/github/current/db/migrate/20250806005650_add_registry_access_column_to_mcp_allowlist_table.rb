# typed: true

class AddRegistryAccessColumnToMcpAllowlistTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_mcp_allowlists, bulk: true do |t|
      t.column :registry_access, :integer, limit: 1, null: false, default: 0, unsigned: true, comment: "Indicates MCP Registry URL access"
    end
  end
end
