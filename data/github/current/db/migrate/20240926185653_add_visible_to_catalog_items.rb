# typed: true
# frozen_string_literal: true

class AddVisibleToCatalogItems < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    add_column :azure_models_catalog_items, :visibility, :integer, default: 0, null: false, after: :value
  end
end
