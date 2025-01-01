class AddOwnerIdToRepositorySecurityCenterStatuses < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_center_statuses, bulk: true do |t|
      t.column :owner_id, :bigint, unsigned: true, null: false, default: 0
      t.column :business_id, :bigint, unsigned: true, null: true

      t.index [:owner_id, :feature_type, :repository_id], name: "index_on_owner_id_feature_type_repository_id"
      t.index [:owner_id, :feature_type, :scanning_status, :repository_id], name: "index_owner_id_feature_scanning_status_repo_id"
      t.index [:owner_id, :repository_id, :feature_type, :scanning_status], name: "index_owner_id_repo_id_feature_type_scanning_status"
      t.index [:owner_id, :feature_type, :scanning_status, :scanning_count, :repository_id], name: "index_owner_id_feature_scanning_status_scanning_count_repo_id"
    end
  end
end
