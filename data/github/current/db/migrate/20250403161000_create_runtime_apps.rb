# typed: true
# frozen_string_literal: true

class CreateRuntimeApps < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :runtime_apps, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, null: false, unsigned: true, comment: "User ID of the app creator"
      t.string :permanent_name, null: false, limit: 255, comment: "Permanent slug of the app used in the default URL"
      t.string :friendly_name, null: true, limit: 255, comment: "User-assigned slug of the app"
      t.string :description, null: true, limit: 255, comment: "User-assigned description of the app"
      t.string :username, null: false, limit: 255, comment: "Login handle of the app creator at time of creation"

      t.timestamps

      t.index :user_id, name: "index_runtime_apps_on_user_id"
      t.index :permanent_name, name: "index_runtime_apps_on_permanent_name", unique: true
    end
  end
end
