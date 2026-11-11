# typed: true
# frozen_string_literal: true

module Billing
  module SharedStorage
    class BillingPlatformReplayFanoutJob < ApplicationJob
      BACKFILL_KEY = "billing_platform_migration.artifact_fanout_completed_at"

      queue_as :billing

      discard_on(StandardError) do |_job, error|
        Failbot.report(error)
      end

      def perform(business:)
        GitHub.dogstats.increment(
            "billing.shared_storage_job_called",
            tags: ["job:billing_platform_replay_fanout_job"]
          )
      end
    end
  end
end
