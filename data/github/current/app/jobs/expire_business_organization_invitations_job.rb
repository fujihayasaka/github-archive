# typed: true
# frozen_string_literal: true

class ExpireBusinessOrganizationInvitationsJob < ApplicationJob
  schedule interval: 1.day

  queue_as :invalidate_expired_invites
  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  BATCH_SIZE = 100

  def perform
    ActiveRecord::Base.connected_to(role: :reading) do
      BusinessOrganizationInvitation.recently_expired.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        with_write do
          batch.each do |invitation|
            BusinessOrganizationInvitation.throttle do
              invitation.expire
            end
          end
        end
      end
    end
  end
end
