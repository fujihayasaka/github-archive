class FixIndexesOnDeployments < ActiveRecord::Migration[7.2]

  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :deployments, bulk: true do |t|
      t.index [:repository_id, :creator_id], name: "index_deployments_on_repository_id_and_creator_id"
      t.remove_index name: "index_deployments_on_repository_id_and_environment"
      t.remove_index name: "index_deployments_on_sha"
    end
  end
end
