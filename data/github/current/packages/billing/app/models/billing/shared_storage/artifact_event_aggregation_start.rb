# typed: true
# frozen_string_literal: true

module Billing::SharedStorage
  class ArtifactEventAggregationStart
    CONCURRENT_FANS = 10
    CONCURRENT_FANS_KV_KEY = "billing.shared_storage.artifact_event_aggregation.concurrent_fans".freeze
    NEXT_RUN_KV_KEY = "billing.shared_storage.artifact_event_aggregation.next_run"

    def self.concurrent_fans
      Billing::Kv.store.get(CONCURRENT_FANS_KV_KEY).value { CONCURRENT_FANS } || CONCURRENT_FANS
    end

    # Start artifact event aggregation for the next cutoff time
    #
    # Loads the appropriate cutoff time from KV, defaulting to the current hour,
    # and enqueues a FanoutAggregationJob to aggregate all artifact events with
    # and effective date before that cutoff time. If the cutoff time in KV is
    # in the future, no FanoutAggregationJob is enqueued as it's not yet time
    # to do any aggregation. In the event that some hours have been missed --
    # that is, the cutoff in KV is more than 1 hour in the past -- then a
    # FanoutAggregationJob is enqueued for each hour that needs to be
    # aggregated, allowing things to self-heal.
    #
    # Returns nothing
    def perform
      cutoff = next_run_time || current_hour
      return if cutoff.future?

      until cutoff.future?
        execution_frequency = FeatureFlag.vexi.enabled_or_raise?(:billing_large_event_windows) ? CurrentUsage::LARGE_EVENT_WINDOW_HOURS.hours : 1.hour # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        new_cutoff = cutoff + execution_frequency

        # Set the next cutoff before we enqueue the job
        # so that we can bail if setting the next cutoff fails
        # to prevent enqueueing the job multiple times
        Billing::Kv.store.set(NEXT_RUN_KV_KEY, new_cutoff.to_i.to_s)

        self.class.concurrent_fans.times do |fan_index|
          FanoutAggregationJob.perform_later(cutoff, fan_index: fan_index, fan_total: self.class.concurrent_fans)
        end

        cutoff = new_cutoff
      end
    rescue GitHub::KV::UnavailableError
      # If KV fails, we want to bail and let the timer retry later
      GitHub.dogstats.increment(
        "billing.shared_storage.aggregation_error",
        tags: ["job:start_aggregation_job", "error:kv_unavailable"],
      )
    end

    private

    def next_run_time
      timestamp = Billing::Kv.store.get(NEXT_RUN_KV_KEY).value!
      Time.at(timestamp.to_i) if timestamp
    end

    def current_hour
      Time.now.beginning_of_hour
    end
  end
end
