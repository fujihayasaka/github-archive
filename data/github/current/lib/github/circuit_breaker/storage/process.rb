# typed: true
# frozen_string_literal: true

# Note: this file omits type annotations because it is performance critical.

require_relative "../storage"
require_relative "snapshot"

module GitHub
  module CircuitBreaker
    module Storage
      # An in-process storage implementation for circuit breaker metrics.
      # This implementation is not thread-safe.
      # Avoids allocating memory to reduce pressure on the garbage collector.
      # The storage is implemented as a ring buffer of buckets, each of which contains a snapshot of the metrics for a given time period.
      # The ring buffer is pruned as needed to keep the sliding window of metrics up to date.
      # Public methods accept a timestamp (in seconds since some epoch) to indicate the time at which the action was taken.
      # However, the storage does not support point-in-time queries of counts (e.g., seeing the number of failures at some point in the past within the current window).
      class Process
        include Storage

        # Initialized the storage with the number of buckets to use for the rolling window and their size in seconds.
        def initialize(buckets:, bucket_size:)
          @buckets = buckets
          @bucket_size = bucket_size
          @loop_point = buckets * bucket_size

          @ring = Array.new(buckets) { Snapshot.new }
          @total = Snapshot.new

          @start_time = nil
          @start_index = 0
        end

        # Increments the number of successful actions taken by the circuit breaker at the given timestamp (in seconds since some epoch).
        # The default amount is 1, but any value (positive or negative) may be used.
        def increment_successes(now, amount: 1)
          prune(now)

          @start_time ||= now
          @total.increment_successes(amount)
          @ring[index(now)].increment_successes(amount)

          nil
        end

        # Increments the number of failed actions taken by the circuit breaker at the given timestamp (in seconds since some epoch).
        # The default amount is 1, but any value (positive or negative) may be used.
        def increment_failures(now, amount: 1)
          prune(now)

          @start_time ||= now
          @total.increment_failures(amount)
          @ring[index(now)].increment_failures(amount)

          nil
        end

        # The count of successful actions taken by the circuit breaker in the current sliding window up to the given timestamp (in seconds since some epoch).
        def successes(now)
          prune(now)

          return 0 unless @start_time

          @total.successes
        end

        # The count of failed actions taken by the circuit breaker in the current sliding window up to the given timestamp (in seconds since some epoch).
        def failures(now)
          prune(now)

          return 0 unless @start_time

          @total.failures
        end

        # The total count of actions taken by the circuit breaker in the current sliding window up to the given timestamp (in seconds since some epoch).
        def total(now)
          prune(now)

          return 0 unless @start_time

          @total.total
        end

        # Resets the storage to its initial state (i.e. an empty sliding window).
        def reset
          @ring.each(&:reset)
          @total.reset

          @start_time = nil
          @start_index = 0

          nil
        end

        private

        # Prunes the ring buffer of buckets that are no longer in the sliding window for the given timestamp (in seconds since some epoch).
        def prune(now)
          # empty storage does not need pruning
          return unless @start_time

          if now < @start_time
            raise ArgumentError, "Timestamp #{now} must be greater than or equal to the start time #{@start_time}"
          end

          elapsed = now - @start_time

          # nothing to prune yet
          return unless elapsed >= @loop_point

          buckets_to_prune = (1.0 * (elapsed - @loop_point) / @bucket_size).floor + 1

          # less work to reset the storage than to prune all buckets
          return reset if buckets_to_prune >= @buckets

          buckets_to_prune.times do
            snapshot = @ring[@start_index]
            @total.decrement_by(snapshot)
            snapshot.reset

            @start_index = (@start_index + 1) % @buckets
          end

          @start_time += @bucket_size * buckets_to_prune

          nil
        end

        # The index into the ring buffer for the given timestamp (in seconds since some epoch).
        def index(now)
          elapsed_time = now - @start_time
          offset = (1.0 * elapsed_time / @bucket_size).floor

          (@start_index + offset) % @buckets
        end
      end
    end
  end
end
