# typed: strict

class CreateSecurityCampaignTeamManagers < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  sig { void }
  def change
    create_table :security_campaign_team_managers, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint  :security_campaign_id,  unsigned: true, null: false
      t.bigint  :team_id,               unsigned: true, null: false

      t.timestamps

      t.index [:security_campaign_id, :team_id], unique: true, name: "index_sc_team_managers_on_sc_id_and_team_id"
    end
  end
end
