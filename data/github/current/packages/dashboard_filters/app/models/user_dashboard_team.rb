# typed: true
# frozen_string_literal: true

# A class representing the user_dashbaord to teams mapping
class UserDashboardTeam < ApplicationRecord::Domain::Users
  belongs_to :user_dashboard
  belongs_to :team
end
