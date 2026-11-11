# typed: true

class CreateCopilotCustomKeys < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_custom_keys, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :name, limit: 60, null: false, comment: "User-given name"
      t.string :kredz_key, limit: 60, null: false, comment: "Identifier for where the key is stored in kredz"
      t.integer :provider, default: 0, null: false
      t.bigint :organization_id, unsigned: true, null: false
      t.text :deployment_url, comment: "Azure deployment URL if applicable"
      t.timestamps

      t.index [:organization_id, :kredz_key], unique: true
      t.index [:organization_id, :name], unique: true
    end
  end
end
