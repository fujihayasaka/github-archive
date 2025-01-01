# typed: true

class CreateSecurityCampaignUsers < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    create_table :security_campaign_users, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint  :security_campaign_id,  unsigned: true, null: false
      t.bigint  :user_id,               unsigned: true, null: false

      t.timestamps

      t.index [:security_campaign_id, :user_id], unique: true, name: "index_sc_users_on_sc_id_and_user_id"
    end
  end
end
