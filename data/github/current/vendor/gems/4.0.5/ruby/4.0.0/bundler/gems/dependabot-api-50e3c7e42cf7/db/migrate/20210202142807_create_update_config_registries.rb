# frozen_string_literal: true

class CreateUpdateConfigRegistries < ActiveRecord::Migration[6.0]
  def change
    create_table :update_config_registries, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.bigint :update_config_id, null: false
      t.string :registry_name, limit: 64, null: false
      t.datetime :created_at,
                 null: false
      t.index %i(update_config_id registry_name),
              unique: true,
              name: "index_update_config_registries_on_config_id_and_name"
    end
  end
end
