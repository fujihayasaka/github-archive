# typed: true

class CreateCopilotCustomModels < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_custom_models, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :name, limit: 60, null: false, comment: "User-provided name"
      t.string :slug, limit: 80, null: false, comment: "Identifier for this model from the provider"
      t.boolean :copilot_chat_enabled, null: false, default: true
      t.bigint :custom_key_id, unsigned: true, null: false, comment: "Reference to custom_keys record"
      t.timestamps

      t.index [:custom_key_id, :name], unique: true
      t.index [:custom_key_id, :slug], unique: true
    end
  end
end
