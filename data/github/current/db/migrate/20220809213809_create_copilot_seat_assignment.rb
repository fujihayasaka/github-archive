# typed: true
class CreateCopilotSeatAssignment < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_seat_assignments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :organization, index: { unique: false }, null: false
      t.references :assignable, polymorphic: true, null: false, index: false
      t.date :pending_cancellation_date, null: true
      t.references :assigning_user, index: { unique: false }, null: false
      t.timestamps

      t.index [:assignable_id, :assignable_type], name: "index_copilot_seat_assignments_on_assignables"
    end
  end
end
