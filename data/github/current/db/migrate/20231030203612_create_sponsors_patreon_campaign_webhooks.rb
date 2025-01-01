# typed: true
# frozen_string_literal: true

class CreateSponsorsPatreonCampaignWebhooks < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    create_table :sponsors_patreon_campaign_webhooks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :sponsors_patreon_user_id, "bigint(20)", unsigned: true, null: false,
        comment: "Foreign key to sponsors_patreon_users"
      t.string :campaign_id, null: false, comment: "Campaign ID on Patreon"
      t.string :webhook_id, null: false, comment: "ID of the webhook on Patreon"
      t.column :secret, "varbinary(8192)", after: :patreon_id,
        comment: "Secret for verifying events triggered by this webhook"
      t.text :triggers, null: false, comment: "List of event types that will trigger the webhook"
      t.timestamps

      t.index [:sponsors_patreon_user_id, :campaign_id], unique: true
      t.index :webhook_id, unique: true
    end
  end
end
