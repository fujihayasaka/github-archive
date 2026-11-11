# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class CustomPropertiesDefinitionsAddUniqueConstraint < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :custom_property_definitions, bulk: true do |t|
      t.remove_index name: "idx_custom_property_definitions_on_source_id_type_and_prop_name"
      t.index [:source_id, :source_type, :property_name], name: "idx_custom_property_definitions_on_source_id_type_and_prop_name", unique: true
    end
  end

  def down
    change_table :custom_property_definitions, bulk: true do |t|
      t.remove_index name: "idx_custom_property_definitions_on_source_id_type_and_prop_name"
      t.index [:source_id, :source_type, :property_name], name: "idx_custom_property_definitions_on_source_id_type_and_prop_name"
    end
  end
end
