# typed: true
# frozen_string_literal: true

class CancelOrganizationInvitationJob < ApplicationJob
  queue_as :cancel_organization_invitation

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(actor:, invitation:, notify: true)
    with_write do
      invitation.cancel(actor: actor, notify: notify)
    end
  end
end
