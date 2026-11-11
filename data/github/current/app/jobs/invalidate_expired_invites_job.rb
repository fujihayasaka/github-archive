# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Responsible for expiring OrganizationInvitations.
class InvalidateExpiredInvitesJob < ApplicationJob
  schedule interval: 1.day

  queue_as :invalidate_expired_invites
  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  BATCH_SIZE = 1000

  def perform
    invitation_ids = OrganizationInvitation.recently_expired.pluck(:id)

    invitation_ids.each_slice(BATCH_SIZE) do |ids|
      OrganizationInvitation.includes(:organization, :inviter, :invitee).where(id: ids).each do |invite|
        OrganizationInvitation.throttle do
          invite.expire
        end
      end
    end
  end
end
