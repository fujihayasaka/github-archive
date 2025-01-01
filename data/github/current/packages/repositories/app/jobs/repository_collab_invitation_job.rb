# typed: true
# frozen_string_literal: true

class RepositoryCollabInvitationJob < ApplicationJob
  queue_as :invite_collaborator_to_repository

  def perform(invitation_id)
    if invitation = RepositoryInvitation.find_by(id: invitation_id)
      RepositoryMailer.collab_invited(invitation).deliver_later

      # summary is not used but the side effect (creating a db record) from this call is
      # relied on by a test.
      summary = with_write { GitHub.newsies.web.rollup_summary_from_repository_invitation(invitation) }
      GitHub.newsies.trigger(
        invitation,
        recipient_ids: [invitation.invitee&.id],
        reason: "invitation",
        event_time: invitation.created_at,
      )
    end
  end
end
