# typed: false
# frozen_string_literal: true

class RepositoryCollabInvitationJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :invite_collaborator_to_repository

  def perform(invitation_id)
    if invitation = RepositoryInvitation.find_by_id(invitation_id)
      RepositoryMailer.collab_invited(invitation).deliver_later

      # summary is not used but the side effect (creating a db record) from this call is
      # relied on by a test.
      summary = GitHub.newsies.web.rollup_summary_from_repository_invitation(invitation)
      GitHub.newsies.trigger(
        invitation,
        recipient_ids: [invitation.invitee.id],
        reason: "invitation",
        event_time: invitation.created_at,
      )
    end
  end
end
