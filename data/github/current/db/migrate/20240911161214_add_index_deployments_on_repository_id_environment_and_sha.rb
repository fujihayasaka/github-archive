# typed: true

class AddIndexDeploymentsOnRepositoryIdEnvironmentAndSha < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    add_index :deployments, [:repository_id, :environment, :sha], name: "index_deployments_on_repository_id_environment_and_sha"
  end
end
