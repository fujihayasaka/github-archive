# typed: true

class AddTypeEtAlToSecurityConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table(:security_configurations, bulk: true) do |t|
      t.column :type, :string, limit: 255, null: true, after: "secret_scanning_validity_checks"
      t.column :secret_protection_sku_enabled, :boolean, null: false, default: false, after: "private_vulnerability_reporting"
      t.column :code_security_sku_enabled, :boolean, null: false, default: false, after: "enable_ghas"
    end
  end
end
