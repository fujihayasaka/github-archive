# typed: true
# frozen_string_literal: true

class DestroyFailedInvitationsToOrgJob < ApplicationJob
  queue_as :background_destroy

  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform(org)
    ActiveRecord::Base.connected_to(role: :reading) do
      org.failed_invitations.in_batches(of: BATCH_SIZE) do |batch|
        ActiveRecord::Base.connected_to(role: :writing) do
          batch.destroy_all
        end
      end
    end
  end
end
