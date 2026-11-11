# typed: true

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class ChangeAzureModelsCatalogItemsKeySize < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def up
    change_table :azure_models_catalog_items, bulk: true do |t|
      t.change :key, :string, limit: 80, null: false
      t.index :key, unique: true
    end
  end

  def down
    change_table :azure_models_catalog_items, bulk: true do |t|
      t.remove_index :key
      t.change :key, :string, limit: 1024, null: false
    end
  end
end
