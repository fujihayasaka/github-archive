# typed: true
# frozen_string_literal: true

class CreateOrganizationCustomPropertyDefinitions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :organization_custom_property_definitions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :source_id, null: false, unsigned: true
      t.integer :source_type, null: false, default: 1, unsigned: true, limit: 1
      t.string :property_name, null: false, limit: 75
      t.integer :value_type, null: false, unsigned: true, limit: 1
      t.string :description, limit: 255
      t.boolean :required, null: false, default: false
      t.integer :values_editable_by, null: false, default: 0, unsigned: true, limit: 1
      t.json :allowed_values
      t.json :config

      t.index [:source_id, :source_type, :property_name], unique: true, name: "idx_org_custom_property_defs_on_source_id_type_and_prop_name"
    end
  end
end
