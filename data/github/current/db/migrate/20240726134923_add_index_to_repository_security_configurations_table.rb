class AddIndexToRepositorySecurityConfigurationsTable < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table(:repository_security_configurations, bulk: true) do |t|
      t.index [:organization_id, :state], name: "index_repository_security_configs_on_organization_id_and_state"
    end
  end
end
