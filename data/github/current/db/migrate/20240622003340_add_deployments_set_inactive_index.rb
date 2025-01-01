class AddDeploymentsSetInactiveIndex < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    change_table :deployments, bulk: true do |t|
      # As part of https://github.com/github/mysql-database-usage/issues/1524, we'll remove the now-duplicate index
      # that doesn't include transient_environment in a separate migration.
      # rubocop:disable GitHub/AvoidRedundantIndex
      t.index [:repository_id, :latest_environment, :latest_status_state, :transient_environment], name: "index_deployments_on_repository_id_latest_status_transient"
    end
  end
end
