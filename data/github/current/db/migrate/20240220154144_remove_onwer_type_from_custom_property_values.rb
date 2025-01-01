class RemoveOnwerTypeFromCustomPropertyValues < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    remove_column :custom_property_values, :owner_type
  end

  def down
    add_column :custom_property_values, :owner_type, :string, limit: 30, null: true
  end
end
