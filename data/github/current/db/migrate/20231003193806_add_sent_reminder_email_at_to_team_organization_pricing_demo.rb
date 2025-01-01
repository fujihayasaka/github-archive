class AddSentReminderEmailAtToTeamOrganizationPricingDemo < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    change_table :team_organization_pricing_demos, bulk: true do |t|
      t.datetime :sent_reminder_email_at, precision: 6
    end
    add_index :team_organization_pricing_demos, :sent_reminder_email_at
  end
end
