class AddNotNullOnRepositorySecurityConfiguration < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_column_null :repository_security_configurations, :organization_id, false
  end
end
