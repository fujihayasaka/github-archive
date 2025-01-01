# typed: true

class AddAccessRevokedAtToCopilotSeatAssignment < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_seat_assignments, bulk: true do |t|
      t.column :access_revoked_at, :datetime, null: true, default: nil, precision: 0
    end
  end
end
