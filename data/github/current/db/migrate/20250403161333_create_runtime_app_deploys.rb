# typed: true
# frozen_string_literal: true

class CreateRuntimeAppDeploys < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :runtime_app_deploys, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :runtime_app_id, null: false, unsigned: true, comment: "Runtime App this deployment belongs to"
      t.string :revision, null: false, limit: 255, comment: "Either the SHA or another identifier for the deployment"
      t.string :display_name, null: true, limit: 255, comment: "User-assigned slug of the app"
      t.text :url, null: true, limit: 255, comment: "URL of the deployed app"

      t.timestamps

      t.index :runtime_app_id, name: "index_runtime_app_deploys_on_runtime_app_id"
    end
  end
end
