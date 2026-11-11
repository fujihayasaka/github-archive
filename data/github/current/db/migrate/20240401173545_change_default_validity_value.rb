class ChangeDefaultValidityValue < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_column_default :soa_secret_scanning_alert_revisions, :alert_validity, from: nil, to: 0
  end
end
