# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Billing
  class UpdateSkippedMeteredLineItemsJob < ApplicationJob
    queue_as :billing

    class InvalidProduct < StandardError; end

    locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 5.minutes

    def perform(billable_owner:)
      # Update submission details in Meuse
      Billing::Api::ClientWrapper.new(billable_owner: billable_owner)
        .update_submission_details(Google::Protobuf::Timestamp.new(seconds: billable_owner.current_metered_billing_cycle_starts_at.to_i))
    end
  end
end
