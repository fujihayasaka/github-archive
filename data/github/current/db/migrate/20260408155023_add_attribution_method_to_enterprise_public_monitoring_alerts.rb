# typed: true

class AddAttributionMethodToEnterprisePublicMonitoringAlerts < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    add_column :enterprise_public_monitoring_alerts, :attribution_method,
      :integer,
      null: false,
      default: 0,
      unsigned: true,
      limit: 1,
      comment: "how the enterprise was attributed to the alert author: 0=membership, 1=verified_domain",
      after: :repository_id
  end
end
