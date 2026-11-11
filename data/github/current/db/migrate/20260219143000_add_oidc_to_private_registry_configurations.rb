# typed: true

class AddOIDCToPrivateRegistryConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :private_registry_configurations, bulk: true do |t|
      # Auth type enum, currently supporting 0=token, 1=username_password, 2=oidc_azure, 3=oidc_aws, 4=oidc_jfrog
      t.integer :auth_type, limit: 1, unsigned: true, null: false, default: 0

      # Provider-specific OIDC configuration stored as JSON.
      # Adding a new provider only requires model code changes, no migration.
      t.json :oidc_config
    end
  end
end
