# typed: true
# frozen_string_literal: true

class AddRulesetIndexToRuleConfigurations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_index :repository_rule_configurations, [:repository_ruleset_id], name: "index_rule_configurations_ruleset_id"
  end
end
