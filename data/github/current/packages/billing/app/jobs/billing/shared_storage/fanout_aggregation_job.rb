# typed: true
# frozen_string_literal: true

module Billing
  module SharedStorage
    class FanoutAggregationJob < ApplicationJob
      queue_as :billing

      discard_on(StandardError) do |_job, error|
        GitHub.dogstats.increment(
          "billing.shared_storage.aggregation_error",
          tags: ["job:fanout_aggregation_job"],
        )

        Failbot.report(error)
      end

      retry_on(GitHub::Restraint::UnableToLock, wait: 5.minutes) do |_job, error|
        GitHub.dogstats.increment(
          "billing.shared_storage.aggregation_error",
          tags: ["job:fanout_aggregation_job"],
        )

        Failbot.report(error)
      end

      exempt_from_tenant_context_requirement

      # Perform the FanoutAggregationJob
      #
      # cutoff - The cutoff time for shared storage artifact events; only events
      #          with an effective_at time before the cutoff will be aggregated
      # fan_index - The index assigned to this job to work on a subset of billable owners
      # fan_total - The total number of jobs that will break apart the billable owners. Used in modulo math.
      def perform(cutoff, fan_index: nil, fan_total: nil)
        ArtifactEventAggregationFanout.new(cutoff: cutoff, fan_index: fan_index, fan_total: fan_total).perform
      end
    end
  end
end
