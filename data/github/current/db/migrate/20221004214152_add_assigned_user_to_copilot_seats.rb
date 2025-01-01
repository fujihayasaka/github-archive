# typed: true
class AddAssignedUserToCopilotSeats < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_reference :copilot_seats, :assigned_user, type: :bigint, unsigned: true, index: { unique: false }, null: false
  end
end
