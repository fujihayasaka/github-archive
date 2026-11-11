# typed: true

class AddIndexToRepositorySecurityConfigurationsOnStateAndUpdatedAt < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    add_index :repository_security_configurations,
              [:state, :updated_at],
              name: "index_repository_security_configs_on_state_and_updated_at"
  end
end
