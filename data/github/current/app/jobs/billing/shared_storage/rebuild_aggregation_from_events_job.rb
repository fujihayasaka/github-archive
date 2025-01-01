# typed: true
# frozen_string_literal: true

module Billing
  module SharedStorage
    # *RebuildAggregationFromEventsJob* will update an owner's aggregations
    # by summing up all aggregated events and re-writing the value to the aggregation
    class RebuildAggregationFromEventsJob < ApplicationJob
      use_primaries ApplicationRecord::Billing

      queue_as :billing_shared_storage

      # Discard comes first so the more specific retries take precedence
      discard_on(StandardError) do |_job, error|
        Failbot.report(error)
      end

      retry_on GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: 20
      retry_on ActiveRecord::QueryCanceled, attempts: 5
      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      def perform(owner_id:, repository_id:)
        owner = User.find(owner_id)

        RebuildAggregationFromEvents.new(owner: owner, repository_id: repository_id).perform
      end
    end
  end
end
