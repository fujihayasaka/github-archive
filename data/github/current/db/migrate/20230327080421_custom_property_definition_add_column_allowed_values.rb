# typed: true

class CustomPropertyDefinitionAddColumnAllowedValues < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_column :custom_property_definitions, :allowed_values, :json, null: true
  end
end
