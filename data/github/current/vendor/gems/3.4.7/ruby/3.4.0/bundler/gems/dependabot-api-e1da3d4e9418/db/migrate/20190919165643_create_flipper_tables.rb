# frozen_string_literal: true

class CreateFlipperTables < ActiveRecord::Migration[6.0]
  def self.up
    create_table :flipper_features, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.string :key, null: false
      t.timestamps null: false
    end
    add_index :flipper_features, :key, unique: true

    create_table :flipper_gates, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.string :feature_key, null: false
      t.string :key, null: false
      t.string :value
      t.timestamps null: false
    end
    add_index :flipper_gates, %i(feature_key key value), unique: true
  end

  def self.down
    drop_table :flipper_gates
    drop_table :flipper_features
  end
end
