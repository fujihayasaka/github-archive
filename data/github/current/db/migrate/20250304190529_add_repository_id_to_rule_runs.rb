# typed: true

class AddRepositoryIdToRuleRuns < ActiveRecord::Migration[8.1]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repository_rule_runs, bulk: true do |t|
      t.column :repository_id, :bigint, unsigned: true

      t.remove_index column: [:repository_rule_configuration_id, :created_at], name: "index_repository_rule_runs_rule_config_id_created_at"
      t.remove_index column: [:repository_rule_suite_id, :rule_provider_id, :rule_provider], name: "index_rule_runs_on_rule_suite_and_provider"

      t.index [:repository_rule_suite_id, :rule_provider_id, :rule_provider, :repository_id], name: "index_rule_runs_on_rule_suite_and_provider_and_repository_id"
    end
  end
end
