# rubocop:disable GitHub/AvoidRedundantIndex
class AddIndexDeploymentsOnRepositoryIdAndEnvironment < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :deployments, bulk: true do |t|
      t.index [:repository_id, :environment]
      t.remove_index column: [:environment_id], name: :index_deployments_on_environment_id
      t.remove_index column: [:latest_environment_id], name: :index_deployments_on_latest_environment_id
    end
  end
end
