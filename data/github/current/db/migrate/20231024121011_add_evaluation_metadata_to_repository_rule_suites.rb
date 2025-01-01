# typed: true

class AddEvaluationMetadataToRepositoryRuleSuites < ActiveRecord::Migration[7.1]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_column :repository_rule_suites, :evaluation_metadata, :json, null: true, default: nil
  end
end
