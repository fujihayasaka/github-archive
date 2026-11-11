# typed: true

class DropAzureModelsUsageDetails < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def up
    drop_table :azure_models_usage_details
  end

  def down
    create_table :azure_models_usage_details, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t| # rubocop:disable GitHub/NoNewTablesOnSharedDbClusters
      t.column :auths_count, :bigint, unsigned: true, null: false
      t.column :user_id, :bigint, unsigned: true, null: false
      t.timestamps

      t.index :user_id, unique: true
    end
  end
end
