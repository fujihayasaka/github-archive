class AddIndexToSponsorsPatreonCampaignWebhooksOnCampaignId < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    change_table :sponsors_patreon_campaign_webhooks, bulk: true do |t|
      t.index [:campaign_id]
    end
  end
end
