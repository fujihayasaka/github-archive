class UpdateDeploymentsIdKsIdxIdToBigInt < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :deployments_id_ks_idx, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false
    end
    change_table :archived_deployments_id_ks_idx, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :deployments_id_ks_idx, bulk: true do |t|
      t.change :id, :int, null: false
    end
    change_table :archived_deployments_id_ks_idx, bulk: true do |t|
      t.change :id, :int, null: false
    end
  end
end
