# typed: true

class IndexCustomPropertyValuesOnDefinitionIdValue < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)
  def change
    change_table :custom_property_values, bulk: true do |t|
      t.index [:definition_id, :value], name:  "index_custom_property_value_on_definition_and_value"
    end
  end
end
