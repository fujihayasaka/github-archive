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
    ActiveRecord::Base.connected_to(role: :reading) do
      invitation_ids = OrganizationInvitation.recently_expired.pluck(:id)

      invitation_ids.each_slice(BATCH_SIZE) do |ids|
        OrganizationInvitation.where(id: ids).each do |invite|
          ActiveRecord::Base.connected_to(role: :writing) do
            OrganizationInvitation.throttle do
              begin
                invite.expire
              rescue ActiveRecord::RecordInvalid, NoMethodError
                next
              end
            end
          end
        end
      end
    end
  end
end
