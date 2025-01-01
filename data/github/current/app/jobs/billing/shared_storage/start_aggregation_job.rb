# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Billing
  module SharedStorage
    class StartAggregationJob < ApplicationJob
      queue_as :billing

      schedule interval: 15.minutes, condition: -> { GitHub.billing_enabled? }

      discard_on(StandardError) do |_job, error|
        GitHub.dogstats.increment(
          "billing.shared_storage.aggregation_error",
          tags: ["job:start_aggregation_job"],
        )

        Failbot.report(error)
      end

      exempt_from_tenant_context_requirement

      # Perform the StartAggregationJob
      def perform
        with_write { ArtifactEventAggregationStart.new.perform }
      end
    end
  end
end
