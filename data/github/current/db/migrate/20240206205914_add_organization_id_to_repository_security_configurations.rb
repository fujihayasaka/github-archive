class AddOrganizationIdToRepositorySecurityConfigurations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    add_column :repository_security_configurations, :organization_id, :bigint, unsigned: true, null: true
  end
end
