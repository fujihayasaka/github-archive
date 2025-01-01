# typed: true
# frozen_string_literal: true

class BusinessOrganizationTransferJob < ApplicationJob
  queue_as :business_organization_transfer
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  exempt_from_tenant_context_requirement

  # Hash lock to prevent multiple jobs for the same org being enqueued concurrently
  locked_by timeout: 10.minutes, key: ->(job) {
    transfer = job.arguments[0]
    transfer.organization_id
  }

  # Public: Transfer an org from one enterprise to another.
  #
  # transfer - The BusinessOrganizationTransfer to perform.
  def perform(transfer)
    with_write do
      transfer.perform!
    end
  end
end
