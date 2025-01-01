# typed: true

class AddAzureModelsCatalogItemsVisibilityIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def up
    change_table :azure_models_catalog_items, bulk: true do |t|
      t.index [:visibility, :key]

      t.index [:has_free_playground, :visibility]
      t.remove_index :has_free_playground
    end
  end

  def down
    change_table :azure_models_catalog_items, bulk: true do |t|
      t.remove_index [:visibility, :key]

      t.index :has_free_playground
      t.remove_index [:has_free_playground, :visibility]
    end
  end
end
