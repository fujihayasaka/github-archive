class CreateStores < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :stores, id: :bigint, unsigned: true, auto_increment: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.datetime :created_at, null: false, precision: 6
      t.datetime :deleted_at, null: true, precision: 6
      t.bigint :owner_id, null: false, unsigned: true
      t.integer :state, null: false, limit: 1, default: 0
    end
  end
end
