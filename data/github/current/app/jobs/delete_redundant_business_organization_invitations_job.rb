# typed: true
# frozen_string_literal: true

class DeleteRedundantBusinessOrganizationInvitationsJob < ApplicationJob
  queue_as :background_destroy

  schedule interval: 1.day, condition: -> { !(GitHub.enterprise? || GitHub.multi_tenant_enterprise?) }

  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform
    BusinessOrganizationInvitation.redundant_invitations.in_batches(of: BATCH_SIZE) do |batch|
      with_write { batch.delete_all }
    end
  end
end
