# typed: strict
# frozen_string_literal: true

module SecurityCenter
  # Runs the Security Center drift detection off the page request and caches the
  # resulting banner state. Locked per owner so concurrent page loads for the same
  # org don't run the detection more than once at a time.
  class OrganizationBackfillCheckJob < ApplicationJob
    queue_as :security_center_reconciliation

    retry_on_dirty_exit

    locked_by(
      timeout: 5.minutes,
      key: ->(job) { "security_center.org_backfill_check:#{job.arguments.dig(0, :owner_id)}" },
    )

    sig { params(owner_id: Integer).void }
    def perform(owner_id:)
      organization = Organization.find_by(id: owner_id)
      return if organization.nil?

      in_progress = organization.perform_security_center_reconciliation_check
      organization.cache_security_center_backfill_state(in_progress)
    end
  end
end
