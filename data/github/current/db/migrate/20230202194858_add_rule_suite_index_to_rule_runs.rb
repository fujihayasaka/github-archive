# typed: true
# frozen_string_literal: true

class AddRuleSuiteIndexToRuleRuns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_index :repository_rule_runs, [:repository_rule_suite_id], name: "index_rule_runs_rule_suite_id"
  end
end
