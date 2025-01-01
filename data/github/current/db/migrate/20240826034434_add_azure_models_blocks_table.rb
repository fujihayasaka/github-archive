class AddAzureModelsBlocksTable < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    create_table :azure_models_blocks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :actor_id, :bigint, unsigned: true, null: false
      t.column :user_id, :bigint, unsigned: true, index: { unique: false }, null: false
      t.column :reason, :string, null: false, limit: 1024
      t.column :state, :tinyint, unsigned: true, default: 0, null: false
      t.timestamps
    end
  end
end
