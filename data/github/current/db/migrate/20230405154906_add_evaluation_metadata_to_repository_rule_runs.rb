# typed: true

class AddEvaluationMetadataToRepositoryRuleRuns < ActiveRecord::Migration[7.1]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_column :repository_rule_runs, :evaluation_metadata, :json, null: true
  end
end
