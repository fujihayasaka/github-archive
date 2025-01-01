# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class JobProgressTracker
    extend T::Sig

    KEY_TTL = 20.minutes.in_seconds
    ORG_IDS_KEY = "security_products_enablement.job_progress_tracker.org_ids"

    attr_reader :org_id, :in_progress_key, :remaining_jobs_key, :total_jobs_key, :repository_ids_key

    sig { params(org_id: Integer).void }
    def initialize(org_id)
      @org_id = org_id
      @in_progress_key = "security_configurations:#{org_id}:in_progress"
      @remaining_jobs_key = "security_configurations:#{org_id}:remaining_jobs"
      @total_jobs_key = "security_configurations:#{org_id}:total_jobs"
      @repository_ids_key = "security_configurations:#{org_id}:repository_ids"
    end

    sig { returns(T::Boolean) }
    def start
      start_timestamp = (Time.now.to_f * 1_000_000).to_i
      started = redis.set(in_progress_key, start_timestamp, ex: KEY_TTL, nx: true)
      if started
        redis.del(remaining_jobs_key, total_jobs_key, repository_ids_key)
        redis.sadd(ORG_IDS_KEY, org_id)
      end

      GitHub.dogstats.increment("security_products_enablement.job_progress_tracker.start", tags: ["started:#{started}"])

      started
    end

    sig { returns(Integer) }
    def finish
      # Get our start timestamp and total job count before we delete them,
      # for observability.
      start_timestamp, total_jobs = redis.mget(in_progress_key, total_jobs_key).map(&:to_i)

      # Calculate and track throughput if any work was done.
      if total_jobs > 0
        finish_timestamp = (Time.now.to_f * 1_000_000).to_i
        throughput = total_jobs.fdiv(finish_timestamp - start_timestamp) * 1_000_000
        magnitude = Math.log10(total_jobs).to_i
        GitHub.dogstats.distribution("security_products_enablement.job_progress_tracker.throughput", throughput, tags: ["magnitude:#{magnitude}"])
        GitHub.dogstats.distribution("security_products_enablement.job_progress_tracker.total_jobs", total_jobs)
      end

      redis.del(in_progress_key, remaining_jobs_key, total_jobs_key)
      redis.srem(ORG_IDS_KEY, org_id)

      GitHub.dogstats.increment("security_products_enablement.job_progress_tracker.finish")

      total_jobs
    end

    sig { returns(Integer) }
    def increment_jobs
      total_jobs = redis.incr(total_jobs_key)
      redis.incr(remaining_jobs_key)
      extend_key_expiries

      GitHub.dogstats.increment("security_products_enablement.job_progress_tracker.increment_jobs")

      total_jobs
    end

    sig { returns(Integer) }
    def decrement_jobs
      remaining_jobs = redis.decr(remaining_jobs_key)
      extend_key_expiries

      GitHub.dogstats.increment("security_products_enablement.job_progress_tracker.decrement_jobs", tags: ["finished:#{remaining_jobs.zero?}"])

      remaining_jobs
    end

    # Returns true if the repository ID was added to the set or false if the
    # given repository ID was not added because it was already in the set or
    # nil was given.
    sig { params(repository_id: T.nilable(Integer)).returns(T::Boolean) }
    def append_repository_id(repository_id)
      return false if repository_id.nil?
      redis.sadd(repository_ids_key, repository_id)
    end

    # Redis stores and returns the repository IDs as strings, so first we map
    # them to integers. Returns nil if no repository IDs are found.
    sig { params(count: Integer).returns(T.nilable(T::Array[Integer])) }
    def pop_repository_ids(count)
      redis.spop(repository_ids_key, count).map(&:to_i).presence
    end

    sig { returns(T::Boolean) }
    def in_progress?
      redis.exists(in_progress_key)
    end

    sig { void }
    def extend_key_expiries
      redis.expire(in_progress_key, KEY_TTL)

      # The TTL for these keys longer than the in-progress keys to help us detect when
      # the job count keys are out of sync. In this scenario, the in-progress key will
      # eventually expires before the job count keys. Our monitoring job can alert us
      # when the in-progress key is missing while the job count keys still exist.
      [total_jobs_key, remaining_jobs_key].each { |k| redis.expire(k, KEY_TTL + 11.minutes.in_seconds) }
    end

    sig { returns(T.nilable(Integer)) }
    def remaining_jobs
      redis.get(remaining_jobs_key)&.to_i
    end

    sig { returns(T.nilable(Integer)) }
    def total_jobs
      redis.get(total_jobs_key)&.to_i
    end

    sig { returns(T::Array[Integer]) }
    def repository_ids
      redis.smembers(repository_ids_key).map(&:to_i)
    end

    sig { returns(Redis) }
    def redis
      GitHub.job_coordination_redis
    end
  end
end
