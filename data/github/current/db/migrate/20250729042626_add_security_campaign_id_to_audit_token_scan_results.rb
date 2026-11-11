# typed: true

class AddSecurityCampaignIdToAuditTokenScanResults < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::TokenScanningService)

  def change
    change_table(:audit_token_scan_results, bulk: true) do |t|
      t.column :security_campaign_id, :bigint, null: true, unsigned: true, comment: "security_campaigns.id for the published campaign to which the token scan result is assigned"
    end
  end
end
