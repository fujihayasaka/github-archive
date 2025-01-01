# typed: true

class DropAssigningUserFromCopilotSeats < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    remove_column :copilot_seats, :assigning_user_id
  end
end
