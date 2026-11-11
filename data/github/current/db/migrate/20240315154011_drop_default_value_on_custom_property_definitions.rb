class DropDefaultValueOnCustomPropertyDefinitions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    remove_column :custom_property_definitions, :default_value
  end

  def down
    add_column :custom_property_definitions, :default_value, :string, limit: 75, null: true
  end
end
