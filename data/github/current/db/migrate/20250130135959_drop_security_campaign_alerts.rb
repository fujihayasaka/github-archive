# typed: strict

class DropSecurityCampaignAlerts < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  sig { void }
  def change
    drop_table :security_campaign_alerts, if_exists: true
  end
end
