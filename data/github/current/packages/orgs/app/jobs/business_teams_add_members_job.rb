# typed: true
# frozen_string_literal: true

class BusinessTeamsAddMembersJob < ApplicationJob
  queue_as :business_teams_add_members_job
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(business_team: BusinessTeam, users: T::Array[User]).void }
  def perform(business_team, users)
    users.each_slice(50) do |group|
      with_write do
        BusinessTeam.throttle do
          business_team.bulk_add_members(group, caller_type: :business_team)
        end
      end
    end
  end
end
