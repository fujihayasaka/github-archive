# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SendBusinessOrganizationInvitationRemindersJob < ApplicationJob
  schedule interval: 1.day

  queue_as :invalidate_expired_invites
  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  BATCH_SIZE = 100

  def perform
    ActiveRecord::Base.connected_to(role: :reading) do
      BusinessOrganizationInvitation.pending.joins(:business).find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch.each do |invitation|
          if invitation.needs_reminder?
            with_write { invitation.send_expiration_reminder }
          end
        end
      end
    end
  end
end
