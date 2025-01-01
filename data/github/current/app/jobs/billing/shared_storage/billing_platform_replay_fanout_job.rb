# rubocop:todo GitHub/EnforcePackageAppStructure
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
        return if Billing::Kv.store.get("#{BACKFILL_KEY}.#{business.customer_id}").value { nil }

        usages = CurrentUsage.where(billable_owner: business).distinct.select(:owner_id, :repository_id)
        usages.each do |usage|
          BillingPlatformReplayJob.perform_later(
              customer_id: business.customer_id,
              owner_id: usage.owner_id,
              repository_id: usage.repository_id
            )
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          Billing::Kv.store.set("#{BACKFILL_KEY}.#{business.customer_id}", Time.now.utc.iso8601, expires: 1.month.from_now)
        end
      end
    end
  end
end
