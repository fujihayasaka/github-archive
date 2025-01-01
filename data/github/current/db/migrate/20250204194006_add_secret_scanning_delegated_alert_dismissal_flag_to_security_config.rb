# typed: true

class AddSecretScanningDelegatedAlertDismissalFlagToSecurityConfig < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)
  def change
    add_column :security_configurations, :secret_scanning_delegated_alert_dismissal, :integer, after: :secret_scanning, unsigned: true, null: true
  end
end
