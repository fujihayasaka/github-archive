# typed: true
# frozen_string_literal: true

class AddTeamIdIndexToUserDashboardTeam < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_index :user_dashboard_teams, :team_id
  end
end
