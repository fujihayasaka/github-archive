class AddBusinessIdToRepositorySecurityCenterConfig < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_center_configs, bulk: true do |t|
      t.column :owner_id, :bigint, unsigned: true, null: false, default: 0
      t.column :owner_type, "enum('USER', 'ORGANIZATION')", null: false, default: "ORGANIZATION"
      t.column :business_id, :bigint, unsigned: true, null: true

      t.index [:owner_id, :name, :repository_id], name: "index_repository_security_center_configs_owner_id_name"
      t.index [:owner_id, :visibility, :repository_id], name: "index_repository_security_center_configs_owner_id_visibility"
      t.index [:owner_id, :archived, :repository_id], name: "index_on_owner_id_and_archived_and_repository_id"
      t.index [:owner_id, :repository_id], name: "index_repository_security_center_configs_on_owner_repo"
      t.index [:owner_id, :last_push, :repository_id], name: "index_repo_security_center_configs_owner_id_last_push_repo_id"

      t.remove_index [:repository_id, :ghas_enabled], name: "index_repo_and_ghas_enabled"
    end
  end
end
