class CustomPropertyDefinitionsDropOrganizationIdColumn < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :custom_property_definitions, bulk: true do |t|
      t.remove_index name: "idx_custom_property_definitions_org_id_source_type_prop_name", column: [:organization_id, :source_type, :property_name]
      t.remove :organization_id
    end
  end

  def down
    change_table :custom_property_definitions, bulk: true do |t|
      t.column :organization_id, :bigint, unsigned: true, null: true, default: nil
      t.index [:organization_id, :source_type, :property_name], name: "idx_custom_property_definitions_org_id_source_type_prop_name"
    end
  end
end
