class AddSecretScanningFieldsToSecurityConfiguration < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :security_configurations, bulk: true do |t|
      t.column :secret_scanning_delegated_bypass, :integer, unsigned: true
      t.column :secret_scanning_push_protection_custom_message, :integer, unsigned: true
    end
  end
end
