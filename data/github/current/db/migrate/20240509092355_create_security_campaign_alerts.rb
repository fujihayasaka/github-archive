class CreateSecurityCampaignAlerts < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    create_table :security_campaign_alerts, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint  :security_campaign_id,  unsigned: true, null: false
      t.bigint  :repository_id,         unsigned: true, null: false
      t.bigint  :logical_alert_number,  unsigned: true, null: false
      t.timestamps

      t.index [:security_campaign_id, :repository_id, :logical_alert_number], unique: true, name: "index_sc_alerts_on_sc_id_and_repo_id_and_logical_alert_number"
    end
  end
end
