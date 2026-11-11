# typed: true

class CreateCopilotCustomModelRules < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_custom_model_rules, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :status, "tinyint(1)", null: false, comment: "Whether the model(s) are enabled by this rule",
        unsigned: false
      t.bigint :target_id, unsigned: true, null: false,
        comment: "The custom key or custom model this rule affects"
      t.string :target_type, limit: 100, null: false,
        comment: "Whether target_id references copilot_custom_models or copilot_custom_keys"
      t.bigint :business_id, unsigned: true, null: false,
        comment: "The enterprise that made this rule"
      t.bigint :organization_id, unsigned: true,
        comment: "The specific org this rule affects, if any"
      t.timestamps

      t.index [:business_id, :target_id, :target_type, :organization_id], unique: true
      t.index [:organization_id, :business_id]
      t.index [:target_id, :target_type]
    end
  end
end
