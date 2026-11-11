# frozen_string_literal: true

class AddUpdaterVersionsTable < ActiveRecord::Migration[7.0]
  def change
    create_table :updater_versions, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.string :env, null: false
      t.string :ecosystem, null: false
      t.string :version, null: false
      t.timestamps
    end

    add_index :updater_versions, %i(env ecosystem), unique: true
  end
end
