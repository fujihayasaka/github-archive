class AddTreeOidToDeployments < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    change_table :deployments, bulk: true do |t|
      t.column :tree_oid, :string, limit: 40, null: true
      t.index [:repository_id, :tree_oid], name: "index_deployments_on_repository_id_and_tree_oid"
    end
  end
end
