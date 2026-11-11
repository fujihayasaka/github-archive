class CustomPropertyDefinitionsAddSourceIdTypeColumn < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :custom_property_definitions, bulk: true do |t|
      # Results in tinyint
      t.integer :source_type, limit: 1, unsigned: true, default: 0, null: false
      t.bigint :source_id, unsigned: true

      t.index [:organization_id, :source_type, :property_name], name: "idx_custom_property_definitions_org_id_source_type_prop_name"
      t.index [:source_id, :source_type, :property_name], name: "idx_custom_property_definitions_on_source_id_type_and_prop_name"

      t.remove_index name: "index_custom_property_definitions_on_org_id_and_property_name", column: [:organization_id, :property_name]
    end
  end
end
