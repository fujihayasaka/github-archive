# typed: true
# frozen_string_literal: true

class CreateOrganizationCustomPropertyValues < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :organization_custom_property_values, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :target_id, null: false, unsigned: true
      t.bigint :definition_id, null: false, unsigned: true
      t.string :value, null: false, limit: 75

      t.index [:definition_id, :value], name: "index_org_custom_property_values_on_definition_and_value"
      t.index [:target_id, :definition_id], name: "index_org_custom_property_values_on_target_id_and_definition_id"
    end
  end
end
