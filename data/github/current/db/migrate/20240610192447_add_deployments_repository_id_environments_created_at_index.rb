class AddDeploymentsRepositoryIdEnvironmentsCreatedAtIndex < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    change_table :deployments, bulk: true do |t|
      t.index [:repository_id, :environment, :created_at], name: "index_deployments_on_repository_id_environment_and_created"
    end
  end
end
