# typed: true
class AddEvaluationMetadataToRepositoryRuleRuns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_column :repository_rule_runs, :evaluation_metadata, :json, null: true
  end
end
