# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class JobProgressTracker
    KEY_TTL = 20.minutes.in_seconds
    ORG_IDS_KEY = "security_products_enablement.job_progress_tracker.org_ids"
    METRIC_PREFIX = "security_products_enablement.job_progress_tracker"

    Error = Class.new(StandardError)
    TotalJobsLockedError = Class.new(Error)
    TotalJobsNotLockedError = Class.new(Error)

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
    def initialize(org_id, business_id = nil)
      @org_id = org_id
      @business_id = business_id
      @in_progress_key = "security_configurations:#{org_id}:in_progress"
      @remaining_jobs_key = "security_configurations:#{org_id}:remaining_jobs"
      @total_jobs_key = "security_configurations:#{org_id}:total_jobs"
      @total_jobs_locked_key = "security_configurations:#{org_id}:total_jobs_locked"
      @repository_ids_key = "security_configurations:#{org_id}:repository_ids"
      @business_ids_key = business_id.present? ? self.class.business_ids_key(T.must(business_id)) : nil
    end

    sig { returns(T::Boolean) }
    def start
      start_timestamp = (Time.now.to_f * 1_000_000).to_i
      started = redis.set(in_progress_key, start_timestamp, ex: KEY_TTL, nx: true)

      if started
        # Because our monitor checks for nil, we want these to start at zero.
        redis.mset(remaining_jobs_key, 0, total_jobs_key, 0)
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

    sig { returns(T::Boolean) }
    def lock_total_jobs
      lock_timestamp = (Time.now.to_f * 1_000_000).to_i
      locked = redis.set(total_jobs_locked_key, lock_timestamp, ex: KEY_TTL, nx: true)

      tags = { locked: }
      increment(:lock_total_jobs, **tags)
      log(:lock_total_jobs, total_jobs:, remaining_jobs:, **tags)

      locked
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

      log(:append_repository_id, repository_id:)
    end

    # Redis stores and returns the repository IDs as strings, so first we map
    # them to integers. Returns nil if no repository IDs are found.
    sig { params(count: Integer).returns(T.nilable(T::Array[Integer])) }
    def pop_repository_ids(count)
      redis.spop(repository_ids_key, count).map(&:to_i).presence
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
        redis.expire(key, KEY_TTL + (ProgressTrackerKeysMonitorJob::INTERVAL * 1.5))
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

    sig { returns(T::Array[Integer]) }
    def repository_ids
      redis.smembers(repository_ids_key).map(&:to_i)
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
