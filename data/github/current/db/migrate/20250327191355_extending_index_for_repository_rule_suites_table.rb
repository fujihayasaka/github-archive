# typed: true

class ExtendingIndexForRepositoryRuleSuitesTable < ActiveRecord::Migration[8.1]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)
  def change
    change_table :repository_rule_suites, bulk: true do |t|
      t.index [:event_action_id, :repository_id], name: "index_repository_rule_suites_event_action_id_and_repo"
    end
  end
end
