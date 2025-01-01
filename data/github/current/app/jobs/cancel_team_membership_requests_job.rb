# typed: true
# frozen_string_literal: true

class CancelTeamMembershipRequestsJob < ApplicationJob
  queue_as :cancel_team_membership_requests

  retry_on_dirty_exit

  def perform(organization_id, user_id)
    return unless org = Organization.find_by(id: organization_id)
    return unless user = User.find_by(id: user_id)

    with_write { org.cancel_team_membership_requests_for(user) }
  end
end
