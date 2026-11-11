# typed: true
# frozen_string_literal: true

class CreateActionsRuleConditions < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::ActionsEnvironments)

  def change
    create_table :actions_rule_conditions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :target, "tinyint(3)", unsigned: true, null: false
      t.bigint :actions_ruleset_id, unsigned: true
      t.json :parameters, null: false
      t.timestamps

      t.index [:actions_ruleset_id], name: "index_actions_rule_conditions_on_ruleset_id"
    end
  end
end
