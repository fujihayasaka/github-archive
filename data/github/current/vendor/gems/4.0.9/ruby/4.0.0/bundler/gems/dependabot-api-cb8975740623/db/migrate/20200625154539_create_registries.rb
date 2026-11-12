# frozen_string_literal: true

class CreateRegistries < ActiveRecord::Migration[6.0]
  def change
    create_table :registries, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.string :name, limit: 64, null: false
      t.string :registry_type, limit: 40, null: false
      t.json :credentials, null: false
      t.string :source_type, null: false
      t.bigint :source_id, null: false
      t.timestamps null: false
      t.index %i(source_type source_id name),
              name: :index_source_name,
              unique: true
    end
  end
end
