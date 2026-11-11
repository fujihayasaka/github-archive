# typed: true
# frozen_string_literal: true

class CreateSavedCollections < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    create_table :saved_collections, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :dashboard_id, unsigned: true, null: false
      t.bigint :priority, unsigned: true
      t.integer :color, default: 0
      t.integer :icon, default: 0
      t.mediumblob :description
      t.string :name, limit: 1024, default: "", null: false
      t.timestamps

      t.index [:dashboard_id, :priority], unique: true
    end
  end
end
