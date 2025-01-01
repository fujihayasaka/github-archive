class AddIndexesToDeployments < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)
  def change
    change_table :deployments, bulk: true do |t|
      t.remove_index name: "index_deployments_on_repository_id_and_ref"
      t.remove_index name: "index_deployments_on_repository_id_and_creator_id"
      t.index [:repository_id, :latest_status_state, :created_at], name: "index_deployments_on_repository_id_latest_status_and_created"
      t.index [:repository_id, :ref, :created_at], name: "index_deployments_on_repository_id_ref_and_created"
      t.index [:repository_id, :creator_id, :created_at], name: "index_deployments_on_repository_id_creator_id_and_created"
    end
  end
end
