# typed: true
# frozen_string_literal: true

class CreateActionsKeyValues < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesActionsChecks)

  def change
    create_table :actions_key_values, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :key, limit: 255, null: false
      t.blob :value, null: false
      t.timestamps
      t.datetime :expires_at, null: true, precision: 6
      t.bigint :partition_key, null: false, unsigned: true

      t.index [:partition_key, :key], unique: true
      t.index :expires_at
    end

    add_vindex :actions_key_values, :hash, :partition_key
    add_auto_increment(:actions_key_values, :id, :actions_key_values_id_seq)
  end
end
