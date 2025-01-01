# typed: true

class AddGenericSecretsFlagToSecurityConfig < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    add_column :security_configurations, :secret_scanning_generic_secrets, :tinyint, unsigned: true, null: true
  end
end
