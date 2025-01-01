class RemoveCustomMessageFromSecurityConfiguration < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    remove_column :security_configurations, :secret_scanning_push_protection_custom_message, :integer
  end
end
