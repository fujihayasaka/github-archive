class RemoveNillableTypeFromCustomPropertyDefinition < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_column_null :custom_property_definitions, :value_type, false
  end
end
