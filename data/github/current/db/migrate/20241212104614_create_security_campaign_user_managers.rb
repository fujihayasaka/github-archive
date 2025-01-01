# typed: strict

class CreateSecurityCampaignUserManagers < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  sig { void }
  def change
    create_table :security_campaign_user_managers, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint  :security_campaign_id,  unsigned: true, null: false
      t.bigint  :user_id,               unsigned: true, null: false

      t.timestamps

      t.index [:security_campaign_id, :user_id], unique: true, name: "index_sc_user_managers_on_sc_id_and_user_id"
    end
  end
end
