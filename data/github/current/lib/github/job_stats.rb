# typed: false
# frozen_string_literal: true

module GitHub
  module JobStats
    # Limit memory usage reporting to once every 30 seconds per job class.
    MEMORY_USAGE_RATE_LIMIT = 30

    class << self
      delegate :enqueued, :error, :error=, :will_retry, :will_retry=,
        :backend_name, :backend_name=, :enqueue_time_ms, :enqueue_time_ms=,
        :enqueue_time_per_backend_ms, :enqueue_count_per_backend_ms,
        :initial_memory_usage, :initial_memory_usage=, :final_memory_usage,
        :final_memory_usage=,
      to: :collector

      alias_method :will_retry?, :will_retry
    end

    def self.collector
      GitHub::DataCollector::JobInstrumenterCollector.get_instance
    end

    def self.reset
      collector.reset
    end

    def self.record_enqueue(job_class:)
      enqueued[job_class] += 1
    end

    def self.enqueue_count(job_class:)
      enqueued[job_class]
    end

    def self.record_error(error, will_retry: false)
      self.error = error
      self.will_retry = will_retry
    end

    def self.fatal_error?
      error && !will_retry
    end

    def self.record_backend_name(name)
      self.backend_name = name
    end

    def self.track_enqueue_time
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      self.enqueue_time_ms += ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1_000).round
    end

    def self.track_enqueue_time_by_backend(backend:)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      enqueue_count_per_backend_ms[backend] += 1
      enqueue_time_per_backend_ms[backend] += ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1_000).round
    end

    # Public: Initialize memory usage tracking before a job starts.
    #
    # Returns nothing.
    def self.memory_usage_reset(job_class:, clock: Time)
      # Disable memory usage tracking in Enterprise.
      return if GitHub.enterprise?

      self.initial_memory_usage = self.final_memory_usage = nil

      # Reporting memory usage requires parsing data out of procfs and can be
      # CPU intensive for hosts with high job volume, so we rate limit by
      # job class.
      memory_usage_rate_limit(key: job_class.to_s, clock: clock) do
        self.initial_memory_usage = GitHub::Memory.usage
      end
    end

    # Public: Record memory usage after a job completes.
    #
    # Returns nothing.
    def self.memory_usage_snapshot
      # Only load this when we have loaded one at the start
      return unless initial_memory_usage

      self.final_memory_usage = GitHub::Memory.usage
    end

    # Public: Report memory usage before and after job execution. If memory
    # usage recording was disabled or didn't succeeded, returns nil. Otherwise,
    # returns an array of [initial_usage, current_usage].
    #
    # Returns [GitHub::Memory::Usage, GitHub::Memory::Usage] or nil.
    def self.memory_usage_report
      return unless initial_memory_usage&.success? && final_memory_usage&.success?

      [initial_memory_usage, final_memory_usage]
    end

    # Separate from the collector since this is intended to live across multiple
    # jobs being processed.
    def self.rate_limiters
      Thread.current[:job_stats_memory_usage_rate_limiters] ||= Hash.new(0)
    end

    def self.memory_usage_rate_limit(key:, clock: Time)
      now = clock.now.to_i
      previous = rate_limiters[key]
      if now - MEMORY_USAGE_RATE_LIMIT > previous
        yield
        rate_limiters[key] = now
      end
    end
  end
end
