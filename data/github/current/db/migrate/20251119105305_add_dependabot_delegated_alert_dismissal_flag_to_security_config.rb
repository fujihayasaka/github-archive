# typed: true

class AddDependabotDelegatedAlertDismissalFlagToSecurityConfig < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)
  def change
    add_column :security_configurations, :dependabot_delegated_alert_dismissal, :integer, after: :dependabot_security_updates, unsigned: true, null: true
  end
end
