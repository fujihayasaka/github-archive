# typed: true
# frozen_string_literal: true

class CreateStoreReplicas < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Spokes)

  def change
    create_table :store_replicas, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :store_id, null: false, unsigned: true
      t.bigint :host_id, null: false, unsigned: true
      t.string :checksum, limit: 16, null: false
      t.integer :state, null: false
      t.integer :read_weight, null: false
      t.timestamps precision: nil

      t.index [:store_id, :host_id], unique: true, name: "index_store_replicas_on_store_id_and_host_id"
      t.index :updated_at, name: "index_store_replicas_on_updated_at"
      t.index :state, name: "index_store_replicas_on_state"
      t.index [:host_id, :state, :store_id], name: "index_store_replicas_on_host_id_and_state_and_store_id"
    end
  end
end
