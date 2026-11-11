# typed: true

# rubocop:disable GitHub/AvoidTypeBeforeId
class CreateCopilotMcpAllowlist < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_mcp_allowlists, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :entity_id, unsigned: true, null: false, comment: "The ID of the entity (business or organization)"
      t.string :entity_type, null: false, limit: 50,  comment: "The type of the entity (Business or Organization)"
      t.text :allowlist_url, null: true, comment: "The MCP allowlist URL"
      t.bigint :updated_by_id, unsigned: true, index: false, null: true, comment: "The user who last updated the record"
      t.timestamps

      t.index [:entity_type, :entity_id], unique: true, name: "index_copilot_mcp_allowlists_on_entity"
    end
  end
end
