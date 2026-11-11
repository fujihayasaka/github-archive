# typed: strict
# frozen_string_literal: true

module ApiVersioning
  # Generic value class representing a single notification wave.
  #
  # A wave defines:
  # - which entities are eligible (those within threshold_days of some date)
  # - how often to repeat the notification (send_cadence)
  # - a namespace for Redis keys (to keep waves from different features isolated)
  #
  # == Deduplication via Redis
  #
  # Two Redis keys are used per wave/cohort/version combination:
  #
  #   running_key  - written atomically (NX) on the first batch page;
  #                  TTL is refreshed on every subsequent page so that long-running
  #                  cohorts do not allow the lock to expire mid-flight.
  #                  Prevents overlapping concurrent runs.
  #
  #   completed_key - written when the final batch page succeeds;
  #                   expires after `send_cadence`. Re-enqueueing is suppressed until
  #                   the key expires, which is what drives the recurring send cadence.
  #
  # == Usage
  #
  # Domain-specific wave sets should be defined in a module that holds constants and
  # delegates for_days_remaining / for_identifier to the class methods here:
  #
  #   EARLY  = NotificationWave.new(identifier: "1year",  threshold_days: 365, send_cadence: 60.days,  namespace: "ns")
  #   URGENT = NotificationWave.new(identifier: "6month", threshold_days: 180, send_cadence: 30.days,  namespace: "ns")
  #   ALL    = [URGENT, EARLY]  # ordered smallest-threshold-first
  #
  class NotificationWave
    # Redis TTL for the in-flight lock per cohort/version/wave. Refreshed on
    # every batch page via #refresh_running_key!, so what this value actually
    # bounds is the maximum gap between successive batch landings (plus a
    # safety margin around total run wall-clock).
    #
    # Sized against two facts that live in sibling classes — keep them in
    # sync if any of the three numbers change:
    #
    #   - BaseDeprecationNotificationJob::BATCH_SIZE (1000) gives a per-batch
    #     wall-clock of ~520 ms steady-state. Total run wall-clock for the
    #     largest cohort (~18.7M users) is projected at ~19 h, driven by the
    #     500 emails/sec throttle floor — batch size barely moves this.
    #   - DeprecationCheckJob's scheduled interval MUST be strictly greater
    #     than this TTL. Otherwise a crashed run's lock would still be live
    #     when the next scheduled tick fires, silently suppressing it.
    #
    # Invariant:  total_wall (~19 h)  <  RUNNING_TTL (48 h)  <  orchestrator_interval
    #
    # 48 h gives ~2.5× headroom over total wall-clock and leaves room for a
    # 3-day orchestrator cadence. Cost of an over-long TTL is bounded: at
    # most one extra orchestrator cycle of suppressed re-dispatch after a
    # true crash.
    RUNNING_TTL = T.let(48.hours, ActiveSupport::Duration)

    sig { returns(String) }
    attr_reader :identifier

    sig { returns(Integer) }
    attr_reader :threshold_days

    sig { returns(ActiveSupport::Duration) }
    attr_reader :send_cadence

    sig { returns(String) }
    attr_reader :namespace

    sig do
      params(
        identifier: String,
        threshold_days: Integer,
        send_cadence: ActiveSupport::Duration,
        namespace: String,
      ).void
    end
    def initialize(identifier:, threshold_days:, send_cadence:, namespace:)
      @identifier     = T.let(identifier,    String)
      @threshold_days = T.let(threshold_days, Integer)
      @send_cadence   = T.let(send_cadence,   ActiveSupport::Duration)
      @namespace      = T.let(namespace,      String)
    end

    # Returns the most specific wave (smallest threshold_days) whose threshold covers
    # days_remaining, or nil if none of the supplied waves apply.
    # Waves must be ordered from smallest threshold to largest for this to work correctly.
    sig { params(days_remaining: Integer, waves: T::Array[NotificationWave]).returns(T.nilable(NotificationWave)) }
    def self.for_days_remaining(days_remaining, waves:)
      waves.find { |wave| days_remaining <= wave.threshold_days }
    end

    # Returns the wave with the given identifier from the supplied list, or nil.
    sig { params(identifier: String, waves: T::Array[NotificationWave]).returns(T.nilable(NotificationWave)) }
    def self.for_identifier(identifier, waves:)
      waves.find { |wave| wave.identifier == identifier }
    end

    # Redis key marking that a cohort/version/wave run is currently in progress.
    sig { params(version: String, cohort: String).returns(String) }
    def running_key(version:, cohort:)
      "#{namespace}:running:#{version}:#{cohort}:#{identifier}"
    end

    # Redis key written after the final batch page completes successfully.
    # Expires after +send_cadence+ so the next dispatch is suppressed until then.
    sig { params(version: String, cohort: String).returns(String) }
    def completed_key(version:, cohort:)
      "#{namespace}:completed:#{version}:#{cohort}:#{identifier}"
    end

    # Marks this cohort/version/wave as completed.
    #
    # We delete running_key in the same operation window so validators/orchestrators
    # don't observe a stale "running" state after successful completion.
    # The completed_key TTL IS the send cadence: DeprecationCheckJob suppresses
    # re-enqueueing while this key exists and re-dispatches once it expires.
    sig { params(version: String, cohort: String).void }
    def mark_completed!(version:, cohort:)
      redis = GitHub.legacy_redis
      redis.set(completed_key(version: version, cohort: cohort), 1, ex: send_cadence.to_i)
      redis.del(running_key(version: version, cohort: cohort))
    end

    # Slides the running_key TTL forward by +RUNNING_TTL+ so that long-running
    # cohorts (many batch pages) do not allow the lock to expire mid-flight.
    # Calling EXPIRE on a key that no longer exists is a Redis no-op, so this
    # is safe to call on every page including after a crash-induced key expiry.
    sig { params(version: String, cohort: String).void }
    def refresh_running_key!(version:, cohort:)
      GitHub.legacy_redis.expire(running_key(version: version, cohort: cohort), RUNNING_TTL.to_i)
    end
  end
end
