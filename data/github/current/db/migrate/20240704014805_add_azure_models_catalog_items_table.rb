class AddAzureModelsCatalogItemsTable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    create_table :azure_models_catalog_items, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :key, :string, null: false, limit: 1024
      t.column :value, :json, null: false

      t.timestamps
    end
  end
end
