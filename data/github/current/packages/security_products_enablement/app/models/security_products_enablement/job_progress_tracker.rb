# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class JobProgressTracker
    KEY_TTL = 20.minutes.in_seconds
    MONITORED_KEY_TTL = KEY_TTL + (ProgressTrackerKeysMonitorJob::INTERVAL * 1.5).to_i
    ORG_IDS_KEY = "security_products_enablement.job_progress_tracker.org_ids"
    METRIC_PREFIX = "security_products_enablement.job_progress_tracker"
    REPOSITORY_ID_BATCH_SIZE = 100_000

    Error = Class.new(StandardError)
    TotalJobsLockedError = Class.new(Error)
    TotalJobsNotLockedError = Class.new(Error)

    Finisher = T.type_alias { T.proc.params(repository_ids: T::Array[Integer]).void }

    attr_reader :org_id, :in_progress_key, :remaining_jobs_key, :total_jobs_key, :total_jobs_locked_key, :repository_ids_key, :business_id, :business_ids_key

    sig { params(business_id: Integer).returns(String) }
    def self.business_ids_key(business_id)
      "security_configurations:business:#{business_id}:org_ids"
    end

    # Helper to determine if any Business jobs are currently running.
    sig { params(business_id: Integer).returns(T::Boolean) }
    def self.business_jobs_running?(business_id)
      redis = GitHub.legacy_redis

      # `scard` returns the number of items in a set, so if it's greater than 0 jobs are still running:
      redis.scard(self.business_ids_key(business_id)) > 0
    end

    sig { params(org_id: Integer, business_id: T.nilable(Integer)).void }
    def initialize(org_id, business_id: nil)
      @org_id = org_id
      @business_id = business_id
      @in_progress_key = "security_configurations:#{org_id}:in_progress"
      @remaining_jobs_key = "security_configurations:#{org_id}:remaining_jobs"
      @total_jobs_key = "security_configurations:#{org_id}:total_jobs"
      @total_jobs_locked_key = "security_configurations:#{org_id}:total_jobs_locked"
      @repository_ids_key = "security_configurations:#{org_id}:repository_ids"
      @business_ids_key = business_id.present? ? self.class.business_ids_key(T.must(business_id)) : nil
      @finishers = T.let([], T::Array[Finisher])
    end

    # Registers a callback to be executed when job tracking finishes successfully.
    # The callback will be called with an array of repository IDs if any were tracked.
    # Multiple callbacks can be registered and will be called in registration order.
    # Note: Callbacks are not thread-safe for concurrent registration.
    sig { params(block: Finisher).void }
    def on_finish(&block)
      @finishers.push(block)
    end

    sig { void }
    def call_finishers
      repository_ids = pop_all_repository_ids
      return if repository_ids.empty?

      @finishers.each do |finisher|
        finisher.call(repository_ids)
      rescue => error
        Failbot.report(error)
      end
    end

    sig { returns(T::Boolean) }
    def start
      start_timestamp = (Time.now.to_f * 1_000_000).to_i
      started = redis.set(in_progress_key, start_timestamp, ex: KEY_TTL, nx: true)

      if started
        # Because our monitor checks for nil, we want these to start at zero.
        redis.mset(remaining_jobs_key, 0, total_jobs_key, 0)
        redis.expire(remaining_jobs_key, MONITORED_KEY_TTL)
        redis.expire(total_jobs_key, MONITORED_KEY_TTL)
        redis.del(repository_ids_key, total_jobs_locked_key)

        redis.sadd(ORG_IDS_KEY, org_id)
        if business_ids_key
          redis.sadd(business_ids_key, org_id)
          redis.expire(business_ids_key, KEY_TTL)
        end
      end

      tags = { started: }
      increment(:start, **tags)
      log(:start, **tags)

      started
    end

    sig { returns(Integer) }
    def finish
      raise TotalJobsNotLockedError if !total_jobs_locked?

      # Get our start timestamp and total job count before we delete them,
      # for observability.
      start_timestamp, total_jobs = redis.mget(in_progress_key, total_jobs_key).map(&:to_i)
      finish_timestamp = (Time.now.to_f * 1_000_000).to_i
      duration = finish_timestamp - start_timestamp

      # Calculate and track throughput if any work was done.
      if total_jobs > 0
        throughput = total_jobs.fdiv(duration) * 1_000_000
        magnitude = Math.log10(total_jobs).to_i
      else
        throughput = nil
        magnitude = nil
      end

      call_finishers
      clear

      tags = { magnitude: }
      distribution(:total_jobs, total_jobs, **tags)
      distribution(:duration, duration, **tags)
      distribution(:throughput, throughput, **tags) if throughput
      increment(:finish, **tags)
      log(:finish, total_jobs:, duration:, **tags)

      total_jobs
    end

    sig { void }
    def clear
      redis.del(in_progress_key, remaining_jobs_key, total_jobs_key, total_jobs_locked_key)
      redis.srem(ORG_IDS_KEY, org_id)
      redis.srem(business_ids_key, org_id) if business_ids_key
    end

    sig { returns(Integer) }
    def increment_jobs
      raise TotalJobsLockedError if total_jobs_locked?

      total_jobs = redis.incr(total_jobs_key)
      remaining_jobs = redis.incr(remaining_jobs_key)
      extend_key_expiries

      increment(:increment_jobs)
      log(:increment_jobs, total_jobs:, remaining_jobs:)

      total_jobs
    end

    # Reverse a prior #increment_jobs when the corresponding child job did not
    # end up being enqueued (e.g. the enqueue raised after we reserved the slot).
    # Decrements both total_jobs and remaining_jobs so the counters stay
    # symmetric: every increment has either a matching child #decrement_jobs
    # (when the child runs) or a matching #rollback_increment_jobs (when the
    # enqueue failed). Without this, total_jobs would drift upward over time
    # and skew the duration/throughput metrics emitted by #finish.
    sig { void }
    def rollback_increment_jobs
      total_jobs = redis.decr(total_jobs_key)
      remaining_jobs = redis.decr(remaining_jobs_key)
      extend_key_expiries

      increment(:rollback_increment_jobs)
      log(:rollback_increment_jobs, total_jobs:, remaining_jobs:)
    end

    sig { returns(T::Boolean) }
    def lock_total_jobs
      lock_timestamp = (Time.now.to_f * 1_000_000).to_i
      locked = redis.set(total_jobs_locked_key, lock_timestamp, ex: MONITORED_KEY_TTL, nx: true)
      finished = (locked || total_jobs_locked?) && remaining_jobs&.zero? || false

      tags = { locked:, finished: }
      increment(:lock_total_jobs, **tags)
      log(:lock_total_jobs, total_jobs:, remaining_jobs:, **tags)

      if finished
        finish # Clean up!
      else
        extend_key_expiries
      end

      finished
    end

    # Decrement the number of jobs left to work. If there's no remaining work
    # to be done *and* we know that there's no more work to be identified,
    # the job progress tracker cleans up after itself by calling #finish.
    #
    # Returns whether progress is finished.
    sig { returns(T::Boolean) }
    def decrement_jobs
      remaining_jobs = redis.decr(remaining_jobs_key)
      total_jobs_locked = total_jobs_locked?
      finished = total_jobs_locked && remaining_jobs.zero?

      tags = { finished:, total_jobs_locked: }
      increment(:decrement_jobs, **tags)
      log(:decrement_jobs, total_jobs:, remaining_jobs:, **tags)

      if finished
        finish # Clean up!
      else
        extend_key_expiries
      end

      finished
    end

    sig { params(repository_id: T.nilable(Integer)).void }
    def append_repository_id(repository_id)
      return if repository_id.nil?

      redis.sadd(repository_ids_key, repository_id)
      extend_key_expiries

      log(:append_repository_id, repository_id:)
    end

    sig { returns(T::Array[Integer]) }
    def pop_all_repository_ids
      repository_ids = []

      loop do
        batch_of_repository_ids = redis.spop(repository_ids_key, REPOSITORY_ID_BATCH_SIZE)&.map(&:to_i)
        break unless batch_of_repository_ids.present?

        repository_ids.concat(batch_of_repository_ids)
        break if batch_of_repository_ids.count < REPOSITORY_ID_BATCH_SIZE
      end

      repository_ids
    end

    sig { returns(T::Boolean) }
    def in_progress?
      redis.exists?(in_progress_key)
    end

    # See #extend_key_expiries and ProgressTrackerKeysMonitorJob for an
    # explanation of this logic.
    sig { returns(T::Boolean) }
    def stalled?
      !in_progress? && !remaining_jobs.nil?
    end

    sig { void }
    def extend_key_expiries
      redis.expire(in_progress_key, KEY_TTL)
      redis.expire(business_ids_key, KEY_TTL) if business_ids_key

      # Setting a longer TTL for remaining_jobs_key helps us detect when the
      # job count keys are out of sync. In this scenario, the in-progress key
      # will eventually expire before remaining_jobs_key. Our monitoring job
      # can alert us when the in-progress key is missing while the job count
      # keys still exist.
      #
      # In addition to remaining_jobs_key, we also further extend
      # total_jobs_key and total_jobs_locked_key because we use their values
      # as metadata when the ProgressTrackerKeysMonitorJob reports a stalled
      # job progress tracker.
      [
        remaining_jobs_key,
        total_jobs_key,
        total_jobs_locked_key,
      ].each do |key|
        redis.expire(key, MONITORED_KEY_TTL)
      end
    end

    sig { returns(T.nilable(Integer)) }
    def remaining_jobs
      redis.get(remaining_jobs_key)&.to_i
    end

    sig { returns(T.nilable(Integer)) }
    def total_jobs
      redis.get(total_jobs_key)&.to_i
    end

    sig { returns(T::Boolean) }
    def total_jobs_locked?
      redis.exists?(total_jobs_locked_key)
    end

    sig { returns(Redis) }
    def redis
      GitHub.legacy_redis
    end

    sig { params(metric: Symbol, tags: T.untyped).void }
    def increment(metric, **tags)
      GitHub.dogstats.increment("#{METRIC_PREFIX}.#{metric}", tags: tags.filter_map { |k, v| "#{k}:#{v}" unless v.nil? })
    end

    sig { params(metric: Symbol, value: Numeric, tags: T.untyped).void }
    def distribution(metric, value, **tags)
      GitHub.dogstats.distribution("#{METRIC_PREFIX}.#{metric}", value, tags: tags.filter_map { |k, v| "#{k}:#{v}" unless v.nil? })
    end

    sig { params(metric: Symbol, tags: T.untyped).void }
    def log(metric, **tags)
      GitHub.logger.info("#{METRIC_PREFIX}.#{metric}", tags.merge(
        "code.namespace": self.class.name,
        "gh.org.id": org_id,
        "gh.business.id": business_id,
      ))
    end
  end
end
