class DropTeamOrganizationPricingDemos < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    drop_table :team_organization_pricing_demos, if_exists: true
  end

  def down
    create_table :team_organization_pricing_demos do |t|
      t.integer :user_id, index: { unique: true }, null: false
      t.integer :referral_organization_id, null: false
      t.integer :repository_id, index: { unique: true }, null: false
      t.timestamps precision: 6
      t.datetime :sent_reminder_email_at, precision: 6
      t.index :sent_reminder_email_at, name: "idx_on_sent_reminder_email_at_1a748c13bd"
    end
  end
end
