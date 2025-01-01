# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CleanUpOldOrganizationInvitationsJob < ApplicationJob
  queue_as :clean_up_organization_invitations
  schedule interval: 6.hours

  RETRYABLE_ERRORS = [
    ActiveRecord::ConnectionTimeoutError,
    ActiveRecord::QueryCanceled,
  ].freeze

  RETRYABLE_ERRORS.each do |error|
    retry_on(error) do |_job, error|
      Failbot.report(error)
    end
  end

  retry_on_dirty_exit
  exempt_from_tenant_context_requirement

  OLD_ORGANIZATION_INVITATION_CUTOFF = 1.year
  BATCH_SIZE = 1000
  MAX_BATCHES = 100

  def perform
    batch = 0
    while (invitations = old_organization_invitations.all).any? do
      with_write { invitations.destroy_all }
      batch += 1
      break if batch > MAX_BATCHES
    end
  end

  def old_organization_invitations
    OrganizationInvitation
      .purgeable
      .where("created_at < ?", OLD_ORGANIZATION_INVITATION_CUTOFF.ago)
      .limit(BATCH_SIZE)
  end
end
