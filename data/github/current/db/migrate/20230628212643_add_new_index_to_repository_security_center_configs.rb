# typed: true

class AddNewIndexToRepositorySecurityCenterConfigs < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_center_configs, bulk: true do |t|
      t.index [:organization_id, :last_push, :repository_id], name: "index_repo_security_center_configs_org_id_last_push_repo_id"
      t.remove_index name: "index_repository_security_center_configs_org_id_last_push"
    end
  end
end
