# typed: false
# frozen_string_literal: true

module Newsies
  class MaintenanceBaseJob < ApplicationJob
    include SloHelper
    include ActiveJob::InitiallyEnqueuedAt
    include GitHub::Tracing

    trace_method(
      :delete_thread_subscription_events,
      span_attribute_extractor: ->(_instance, *args, **_kwarg) do
        { "gh.notifications.subscription.count" => args[0].size }
      end
    )

    queue_as :notifications_maintenance

    RESTRAINT_LOCK_KEY = "notifications-maintenance-lock"
    RESTRAINT_LOCK_CONCURRENT_JOBS = 10
    RESTRAINT_LOCK_TTL = 10.minutes
    # the maximum length of list_hashes that _should_ be passed to the job
    MAX_LIST_SIZE = 1000
    # batch size for iterating the users in the job to ensure we throttle queries appropriately
    BATCH_SIZE = 10

    # Map from (inclusive) upper bound of a timing measurement to Datadog tag for SLO bucket.
    SLO_BUCKETS_MS = [
      # upper bound ms, tag name
      [1.second.in_milliseconds,   "bucket:0s-1s"],
      [10.seconds.in_milliseconds, "bucket:1s-10s"],
      [1.minute.in_milliseconds,   "bucket:10s-1m"],
      [5.minutes.in_milliseconds,  "bucket:1m-5m"],
      [20.minutes.in_milliseconds, "bucket:5m-20m"],
      [Float::INFINITY,            "bucket:20m-plus"]
    ]

    retry_on_recoverable_exceptions

    # We wait a random amount of time so that we don't force jobs
    # to wait longer than they have to if more than one job is attempting to
    # grab the lock at the same time.
    retry_on GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: 10 do |_job, _error|
      # Do not propagate the error to the queuing system, as we don't want to raise this error in sentry
      # instead we just log to datadog.
      GitHub.dogstats.increment("newsies.maintenance.unable_to_lock_attempts_exceeded", tags: [*@datadog_tags])
    end

    retry_on_dirty_exit

    around_perform do |_job, block|
      concurrency = RESTRAINT_LOCK_CONCURRENT_JOBS
      if GitHub.flipper[:notifications_duplicate_maintenance_jobs_concurrency].enabled?
        concurrency *= 2
      end
      GitHub::Restraint.new.lock!(RESTRAINT_LOCK_KEY, concurrency, RESTRAINT_LOCK_TTL) do
        block.call
      end

      record_time_to_perform
    end

    def record_time_to_perform
      time_to_perform_ms = (Time.now.utc.to_f - initially_enqueued_at.to_f) * 1000.0
      GitHub.dogstats.timing("newsies.maintenance.time_to_perform", time_to_perform_ms, tags: [
        "class:#{self.class.name.underscore}",
        slo_bucket_tag(SLO_BUCKETS_MS, time_to_perform_ms),
        *@datadog_tags,
      ])
    end

    private

    def delete_thread_subscription_events(subscription_ids, batch_size: BATCH_SIZE)
      SubscriptionEvent.where(
        subscription_type: ThreadSubscription.name,
        subscription_id: subscription_ids,
      ).in_batches(of: batch_size) do |scope|
        SubscriptionEvent.throttle_writes { scope.delete_all }
      end
    end
  end
end
