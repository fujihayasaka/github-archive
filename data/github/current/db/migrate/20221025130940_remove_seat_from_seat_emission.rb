# typed: true
class RemoveSeatFromSeatEmission < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    remove_column :copilot_seat_emissions, :seat_id
  end
end
