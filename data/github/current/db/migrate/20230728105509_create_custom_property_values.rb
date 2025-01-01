# typed: true

class CreateCustomPropertyValues < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :custom_property_values, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :owner_type, limit: 30, null: false
      t.bigint :target_id, unsigned: true, null: false
      t.string :target_type, limit: 30, null: false
      t.bigint :definition_id, unsigned: true, null: false
      t.string :value, limit: 75, null: false

      t.index [:target_id, :definition_id, :target_type], name: "index_custom_property_value_on_target_and_definition"
    end
  end
end
