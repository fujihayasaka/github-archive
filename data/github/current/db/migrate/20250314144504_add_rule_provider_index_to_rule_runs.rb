# typed: true

class AddRuleProviderIndexToRuleRuns < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_index :repository_rule_runs, [:rule_provider_id, :rule_provider, :repository_rule_suite_id, :repository_id], name: "index_rule_runs_on_provider_and_rule_suite_and_repository_id"
  end
end
