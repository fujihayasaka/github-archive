# typed: true

class RemoveStaticModelFromAzureModelsCatalogItems < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    remove_column :azure_models_catalog_items, :static_model, :boolean, null: false, default: false
  end
end
