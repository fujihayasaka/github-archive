class DropOrganizationIdFromRepositorySecurityCenterConfigs < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_center_configs, bulk: true do |t|
      t.remove_index name: :index_repository_security_center_configs_org_id_name
      t.remove_index name: :index_repository_security_center_configs_org_id_visibility
      t.remove_index name: :index_on_organization_id_and_archived_and_repository_id
      t.remove_index name: :index_repository_security_center_configs_on_org_repo
      t.remove_index name: :index_repo_security_center_configs_org_id_last_push_repo_id

      t.remove :organization_id
    end
  end
end
