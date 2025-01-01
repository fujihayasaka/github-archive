# typed: strict
# frozen_string_literal: true

class SlottedCounterIncrementAggregatedJob < AggregatedJob
  queue_as :slotted_counters
  retry_on_dirty_exit

  # How many concurrent jobs with the same key are allowed.
  # This job is reading the shared state from Redis and writing it to MySQL.
  # To avoid reading the same state and writing duplicates multiple times, we don't want any concurrent jobs.
  MAX_CONCURRENT_JOBS = 1

  # Number of seconds representing when this key should be expired if the process is terminated abnormally.
  #
  # That basically means how long a running (or crashed) job is allowed to hold onto a lock,
  # before it expires and another one takes over.
  #
  # We don't expect this to be a long-running job. So few minutes should be enough.
  # At the same time the TTL shouldn't be too high, to allow retry_on UnableToLock to succeed at some point.
  LOCK_TTL = T.let(10.minutes.to_i, Integer)

  # 8 attempts mean that we wait, before discarding the job because retries have been exhausted, for
  # a total of 4690 seconds at a minimum. This roughly means we wait a total of 1h and ~18 min excluding
  # the random component of the algorithm (an additional 0-15% per wait interval).
  #
  # The purpose of this is that the minimum window should cover any incident we have and that we
  # should not have to replay items manually.
  retry_on GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: 8

  sig { params(record_type: String, record_id: Integer, interval: Integer, interval_timestamp: Integer).void }
  def perform(record_type, record_id, interval:, interval_timestamp:)
    # We use restraint lock here in case there is a failure or redelivery that could result in duplicate writes
    GitHub::Restraint.new.lock!(restraint_lock_key, MAX_CONCURRENT_JOBS, LOCK_TTL) do
      if aggregated_value.present?
        SlottedCounterService.increment_type_and_id(record_type, record_id, aggregated_value)
      else
        GitHub.dogstats.increment("slotted_counter_increment_aggregated_job.aggregated_value.missing")
      end
    end
  end

  private

  # We never want to wait for replication since we don't make any queries
  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def replication_state_to_persist
    {}
  end
end
