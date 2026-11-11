# typed: true

class AddIndexOnRequesterIdTeamMembershipRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :team_membership_requests, bulk: true do |t|
      t.index [:requester_id]
      t.change :id, :bigint, unsigned: true, null: false
      t.change :requester_id, :bigint, unsigned: true, null: false
      t.change :team_id, :bigint, unsigned: true, null: false
    end
  end
end
