# typed: true

class CreateCopilotSeat < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_seats, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :organization, index: { unique: false }, null: false
      t.references :copilot_seat_assignment, index: { unique: false }, null: false
      t.references :assigning_user, index: { unique: false }, null: false
      t.timestamps
    end
  end
end
