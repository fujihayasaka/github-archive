# typed: true
# frozen_string_literal: true

class CreateCopilotSettingRulesTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_setting_rules, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :setting_id, unsigned: true, null: false
      t.bigint :condition_expression_id, unsigned: true, null: false
      t.string :rule_type, limit: 255, null: false
      t.integer :priority, unsigned: true, null: false, default: 0
      t.json :parameters
      t.timestamps

      t.index [:setting_id], name: "index_copilot_setting_rules_on_setting_id"
    end
  end
end
