# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Billing
  module SharedStorage
    class AggregationJob < ApplicationJob
      use_primaries ApplicationRecord::Billing

      queue_as :metered_billing

      discard_on(StandardError) do |_job, error|
        GitHub.dogstats.increment(
          "billing.shared_storage.aggregation_error",
          tags: ["job:aggregation_job"],
        )

        Failbot.report(error)
      end

      retry_on(GitHub::Restraint::UnableToLock, wait: 5.minutes) do |_job, error|
        GitHub.dogstats.increment(
          "billing.shared_storage.aggregation_error",
          tags: ["job:aggregation_job"],
        )

        Failbot.report(error)
      end
      retry_on ActiveRecord::QueryCanceled, attempts: 5
      retry_on WaitForReplication::DataUnavailable, wait: 5.minutes # we can wait for replication CurrentUsage#update_from_events_through!
      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      exempt_from_tenant_context_requirement

      # Perform the AggregationJob for a given user
      #
      # owner_id - the id of the owner having their shared storage aggregated
      # cutoff - The cutoff time for shared storage artifact events; only events
      #          with an effective_at time before the cutoff will be aggregated
      def perform(cutoff:, owner_id:)
        ArtifactEventAggregator.new(cutoff: cutoff, owner_id: owner_id).perform
      end
    end
  end
end
