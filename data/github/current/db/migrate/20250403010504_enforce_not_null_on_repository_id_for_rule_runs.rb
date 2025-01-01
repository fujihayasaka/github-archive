# typed: true

class EnforceNotNullOnRepositoryIdForRuleRuns < ActiveRecord::Migration[8.1]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_column_null :repository_rule_runs, :repository_id, false
  end

end
