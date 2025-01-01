# typed: true

class CreateCopilotSeatEmissions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_seat_emissions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # Even if this is an Enterprise based organization, we still track it at the organization level.
      t.references :organization, null: false, index: true, comment: "The organization that this seat emission is for"
      t.references :seat, null: false, index: true, comment: "The Copilot::Seat that this emission is for"
      t.json       :emission, null: false, comment: "The emission message (in JSON) that was sent"

      # these are the required fields for Meuse
      t.string     :unique_id, limit: 36, null: false, index: true, comment: "UUID - The unique ID of the seat emission"
      t.datetime   :occurred_at, precision: 6, null: false, index: true, comment: "The date/time that the seat emission occurred"
      t.decimal    :quantity, precision: 22, scale: 9, default: 0, null: false, comment: "The quantity of the seat emission"
      t.timestamps
    end
  end
end
