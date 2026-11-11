class DropOrganizationIdFromRepositorySecurityCenterStatuses < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_center_statuses, bulk: true do |t|
      t.remove_index name: :index_on_organization_id_feature_type_repository_id
      t.remove_index name: :index_org_id_feature_scanning_status_repo_id
      t.remove_index name: :index_org_id_repo_id_feature_type_scanning_status
      t.remove_index name: :index_org_id_feature_scanning_status_scanning_count_repo_id

      t.remove :organization_id
    end
  end
end
