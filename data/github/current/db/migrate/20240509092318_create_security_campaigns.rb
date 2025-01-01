class CreateSecurityCampaigns < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityCampaigns)

  def change
    create_table :security_campaigns, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references  :organization,        null: false
      t.string      :name,                limit: 50, null: false
      t.string      :description,         limit: 255, null: false
      t.datetime    :ends_at,             null: false, precision: 6
      t.timestamps
    end
  end
end
