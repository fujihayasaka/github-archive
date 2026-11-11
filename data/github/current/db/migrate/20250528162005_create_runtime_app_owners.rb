# typed: true
# frozen_string_literal: true

class CreateRuntimeAppOwners < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :runtime_app_owners, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :owner_id, null: false, unsigned: true, comment: "User/Org ID of this Spark owner"
      t.string :permanent_name, null: false, limit: 20, comment: "Permanent identifier to use with ACA"
      t.string :last_seen_login, null: false, limit: 255, comment: "Last seen login for user/org"
      t.string :deploy_login, null: true, limit: 20, comment: "Name to use with ACA on deployment"
      t.timestamps

      t.index :owner_id, name: "index_runtime_app_owners_on_owner_id", unique: true
      t.index :permanent_name, name: "index_runtime_app_owners_on_permanent_name", unique: true
    end
  end
end
