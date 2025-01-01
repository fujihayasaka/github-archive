class AddSecretScanningNonProviderPatternsToSecurityConfigurations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    add_column :security_configurations, :secret_scanning_non_provider_patterns, :integer, unsigned: true
  end
end
