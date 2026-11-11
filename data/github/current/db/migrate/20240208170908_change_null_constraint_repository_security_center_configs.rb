class ChangeNullConstraintRepositorySecurityCenterConfigs < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def up
    change_column_null :repository_security_center_configs, :organization_id, true
  end

  def down
    change_column_null :repository_security_center_configs, :organization_id, false
  end
end
