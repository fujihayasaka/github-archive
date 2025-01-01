# typed: true
# frozen_string_literal: true

class RetryFailedOrganizationInvitationJob < ApplicationJob
  queue_as :invalidate_expired_invites

  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform(org, actor)
    invitation_ids = []
    email_or_invitee_logins = []

    org.failed_invitations.where(cancelled_at: nil).in_batches(of: BATCH_SIZE) do |batch|
      batch.each do |invitation|
        with_write { invitation.cancel(actor: actor, notify: false) }
        invitation.instrument_retry_invite(actor: actor)
        email_or_invitee_logins << invitation.email_or_invitee_login
        invitation_ids << invitation.id
      end
    end

    OrganizationBulkInviteJob.perform_later \
      actor,
      org,
      email_or_invitee_logins,
      invitation_ids
  end
end
