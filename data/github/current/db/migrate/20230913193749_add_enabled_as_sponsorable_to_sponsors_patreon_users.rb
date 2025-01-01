class AddEnabledAsSponsorableToSponsorsPatreonUsers < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    add_column :sponsors_patreon_users, :enabled_as_sponsorable, :boolean, null: false, default: false
  end
end
