# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/AvoidRedundantIndex

class AddOrgUserAssignmentIndexToCopilotSeats < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    add_index :copilot_seats, [:organization_id, :assigned_user_id, :copilot_seat_assignment_id],
      name: "index_copilot_seats_on_org_user_assignment"
  end
end
