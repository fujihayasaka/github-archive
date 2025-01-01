class RemovePatreonCampaignIdFromSponsorsPatreonUsers < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def up
    change_table :sponsors_patreon_users, bulk: true do |t|
      t.remove :patreon_campaign_id
      t.remove :patreon_campaign_amount_in_cents
    end
  end

  def down
    change_table :sponsors_patreon_users, bulk: true do |t|
      t.string :patreon_campaign_id, after: "patreon_refresh_token"
      t.integer :patreon_campaign_amount_in_cents, after: "patreon_campaign_id"
    end
  end
end
