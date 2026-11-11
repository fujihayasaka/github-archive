# typed: true
# frozen_string_literal: true

class CreateActionsRuleConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::ActionsEnvironments)

  def change
    create_table :actions_rule_configurations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :rule_type, limit: 100, null: false
      t.bigint :actions_ruleset_id, unsigned: true
      t.bigint :created_by_id, unsigned: true
      t.bigint :updated_by_id, unsigned: true
      t.json :parameters
      t.timestamps

      t.index [:actions_ruleset_id], name: "index_actions_rule_configs_on_ruleset_id"
    end
  end
end
