# frozen_string_literal: true

class AddGroupRules < ActiveRecord::Migration[7.0]
  def change
    create_table :group_rules, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.string :name, null: false
      t.references :update_config

      t.timestamps
    end

    add_index :group_rules, %i(name update_config_id), unique: true
  end
end
