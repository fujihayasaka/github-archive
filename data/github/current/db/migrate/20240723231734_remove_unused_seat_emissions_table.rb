class RemoveUnusedSeatEmissionsTable < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Billing)
  def change
    drop_table :seat_emissions
  end
end
