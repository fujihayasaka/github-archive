# typed: true

class AddReplacesBaseToPrivateRegistryConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    add_column :private_registry_configurations, :replaces_base, :boolean, null: false, default: false
  end
end
