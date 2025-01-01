class ChangeNullOwnerTypeCustomPropertyValues < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_column_null :custom_property_values, :owner_type, true
  end

  def down
    change_column_null :custom_property_values, :owner_type, false
  end
end
