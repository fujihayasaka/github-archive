# typed: true
class AddEmittedToSeatEmissions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    add_column :seat_emissions, :emitted_at, :datetime, precision: 6, null: true,
      comment: "whether or not the seat emission has been emitted to the billing system"
  end
end
