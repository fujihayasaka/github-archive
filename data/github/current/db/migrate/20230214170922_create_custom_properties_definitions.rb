# typed: true

class CreateCustomPropertiesDefinitions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :custom_property_definitions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :organization_id, unsigned: true, null: false
      t.string :property_name, null: false, limit: 75
      t.index [:organization_id, :property_name], unique: true, name: "index_custom_property_definitions_on_org_id_and_property_name"
    end
  end
end
