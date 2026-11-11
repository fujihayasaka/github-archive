# typed: true

# rubocop:disable GitHub/OneTablePerMigration

class DropRuleInsightsTablesInRepositoriesCluster < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    return unless (Rails.env.test? || Rails.env.development?) && !GitHub.enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    drop_table :repository_rule_runs, if_exists: true
    drop_table :repository_rule_suites, if_exists: true
    drop_table :repository_rule_suite_source_results, if_exists: true
    drop_table :event_action_ref_updates, if_exists: true
    drop_table :event_action_repository_operations, if_exists: true
  end
end
