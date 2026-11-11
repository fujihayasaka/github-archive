class AddValidityChecksFlagToSecurityConfig < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    # add nullable int unsigned column secret_scanning_validity_checks
    add_column :security_configurations, :secret_scanning_validity_checks, :integer, unsigned: true, null: true
  end
end
