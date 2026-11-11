# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ExpireBusinessAdminInvitationsJob < ApplicationJob
  schedule interval: 1.day

  queue_as :invalidate_expired_invites
  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  BATCH_SIZE = 100

  def perform
    scope = BusinessAdministratorInvitation.preload(:business).recently_expired
    scope.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each do |invitation|
        BusinessAdministratorInvitation.throttle do
          invitation.expire
        end
      end
    end
  end
end
