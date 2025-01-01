# typed: true

class AddIndexToRepositorySecurityConfigurationsOnOrgSecurityConfigRepo < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    add_index :repository_security_configurations,
              [:organization_id, :security_configuration_id, :repository_id],
              name: "index_repo_security_configs_on_org_security_config_repo"
  end
end
