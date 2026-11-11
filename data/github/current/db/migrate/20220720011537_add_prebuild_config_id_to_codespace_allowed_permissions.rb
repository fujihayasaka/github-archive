# typed: true

class AddPrebuildConfigIdToCodespaceAllowedPermissions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    change_table(:codespace_allowed_permissions, bulk: true) do |t|
      t.remove_index [:repository_id, :user_id, :is_prebuild, :target_id, :target_type, :resource, :action]
      t.index [:repository_id, :user_id, :is_prebuild, :codespace_prebuild_configuration_id, :target_id, :target_type, :resource, :action], unique: true, name: "index_codespace_prms_on_repo_user_prbld_trgt_prms"
    end
  end
end
