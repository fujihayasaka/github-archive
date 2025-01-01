# typed: true

class DropAzureModelsPresets < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def up
    drop_table :azure_models_presets
  end

  def down
    create_table :azure_models_presets, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t| # rubocop:disable GitHub/NoNewTablesOnSharedDbClusters
      t.column :user_id, :bigint, unsigned: true, null: false
      t.string :url_identifier, null: false
      t.string :name, null: false
      t.boolean :private, default: true, null: false
      t.json :conversation_history, null: true
      t.json :parameters, null: false

      t.timestamps

      t.index :url_identifier, unique: true
      t.index [:user_id, :name], unique: true
    end
  end
end
