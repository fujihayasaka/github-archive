class DelegatedBypassConfigurationNotNil < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_column_null :security_configurations, :secret_scanning_delegated_bypass, false
  end
end
