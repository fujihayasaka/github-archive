# typed: true

class AddCodespacePrebuildConfigurationIdToCodespaceAllowedPermissions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    add_column :codespace_allowed_permissions, :codespace_prebuild_configuration_id, :bigint, unsigned: true, null: true
  end
end
