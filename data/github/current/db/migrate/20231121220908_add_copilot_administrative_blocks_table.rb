class AddCopilotAdministrativeBlocksTable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_administrative_blocks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :actor_id, :bigint, unsigned: true, null: false
      t.references :blockable, polymorphic: true, index: { unique: false }, null: false
      t.column :reason, :string, null: false, limit: 1024
      t.column :state, :tinyint, unsigned: true, default: 0, null: false
      t.timestamps
    end
  end
end
