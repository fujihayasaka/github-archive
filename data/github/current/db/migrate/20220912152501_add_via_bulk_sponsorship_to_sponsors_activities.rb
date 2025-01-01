# typed: true

class AddViaBulkSponsorshipToSponsorsActivities < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    add_column :sponsors_activities, :via_bulk_sponsorship, :boolean, null: false, default: false
  end
end
