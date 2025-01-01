# typed: true
# frozen_string_literal: true

class DestroyFailedRepositoryInvitationsToOrgJob < ApplicationJob
  queue_as :background_destroy

  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform(org)
    ActiveRecord::Base.connected_to(role: :reading) do
      org.failed_repo_invitations.in_batches(of: BATCH_SIZE) do |batch|
        with_write { batch.destroy_all }
      end
    end
  end
end
