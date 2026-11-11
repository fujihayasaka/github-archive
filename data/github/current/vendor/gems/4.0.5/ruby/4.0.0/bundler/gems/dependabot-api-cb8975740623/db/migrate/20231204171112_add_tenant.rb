# frozen_string_literal: true

class AddTenant < ActiveRecord::Migration[7.0]
  def change
    create_table :tenants, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.string :slug, null: false
      t.integer :github_id, null: false

      t.timestamps
    end

    add_index :tenants, :github_id, unique: true
  end
end
