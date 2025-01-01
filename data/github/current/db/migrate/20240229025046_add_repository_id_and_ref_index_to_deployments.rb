class AddRepositoryIdAndRefIndexToDeployments < ActiveRecord::Migration[7.2]

  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :deployments, bulk: true do |t|
      t.index [:repository_id, :ref], name: "index_deployments_on_repository_id_and_ref"
    end
  end

end
