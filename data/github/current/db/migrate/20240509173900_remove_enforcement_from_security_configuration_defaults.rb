class RemoveEnforcementFromSecurityConfigurationDefaults < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    remove_column :security_configuration_defaults, :enforcement, :tinyint, unsigned: true, default: 0, null: false
  end
end
