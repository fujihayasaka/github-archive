class AddForceDisabledToEnum < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::RepositoriesNotify

  def change
    change_table :vulnerability_alert_rules, bulk: true do |t|
      t.change :enablement_behavior, "enum('disabled_by_default', 'enabled_by_default', 'force_enabled', 'enabled_by_default_for_public', 'force_disabled')", null: false
    end
  end
end
