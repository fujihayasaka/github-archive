# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CancelBusinessAdministratorInvitationJob < ApplicationJob
  queue_as :cancel_business_administrator_invitation

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |args|
    args[:invitation]&.business
  end

  def perform(actor:, invitation:, notify: true)
    with_write do
      invitation.cancel(actor: actor, notify: notify)
    end
  end
end
