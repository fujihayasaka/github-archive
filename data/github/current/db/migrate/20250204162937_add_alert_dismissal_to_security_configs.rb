# typed: true

class AddAlertDismissalToSecurityConfigs < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::RepositoriesNotify

  def change
    add_column :security_configurations, :code_scanning_delegated_alert_dismissal, :integer, unsigned: false,
      after: :code_scanning, limit: 1, null: true
  end
end
