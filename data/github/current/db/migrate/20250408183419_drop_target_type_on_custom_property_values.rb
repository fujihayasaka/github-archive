# typed: true

class DropTargetTypeOnCustomPropertyValues < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :custom_property_values, bulk: true do |t|
      t.index [:target_id, :definition_id],
        name: "index_custom_property_value_on_target_id_and_definition_id"
      t.remove_index name: "index_custom_property_value_on_target_and_definition"
      t.remove :target_type
    end
  end

  def down
    change_table :custom_property_values, bulk: true do |t|
      t.string :target_type, limit: 30, null: true
      t.index [:target_id, :definition_id, :target_type],
        name: "index_custom_property_value_on_target_and_definition"
      t.remove_index name: "index_custom_property_value_on_target_id_and_definition_id"
    end
  end
end
