# typed: strict
# frozen_string_literal: true

module Search
  # Coordinates bulk search indexing so IssueTriageJob can defer success! until
  # all AddToSearchIndexJobs complete and ES has refreshed.
  #
  # Redis keys (all with TTL):
  #   search:bulk_index:count:{job_status_id}          - pending issue count
  #   search:bulk_index:meta:{job_status_id}           - job status class name
  #   search:bulk_index:awaiting:issue:{issue_id}      - SET of job_status_ids
  module BulkIndexCoordination
    REDIS_KEY_PREFIX = "search:bulk_index"
    DEFAULT_TTL = T.let(10.minutes.to_i, Integer)
    ES_REFRESH_INTERVAL = T.let(1, Integer)
    ALLOWED_JOB_STATUS_CLASSES = T.let(
      %w[JobStatus JobStatusSubscription Issues::JobStatus Issues::JobStatusSubscription].freeze,
      T::Array[String],
    )

    sig { returns(T.untyped) }
    def self.redis
      Search::JobCoordination.redis
    end

    # Set up coordination before enqueuing AddToSearchIndexJobs.
    sig do
      params(
        job_status_id: String,
        job_status_class: String,
        issue_ids: T::Array[Integer],
        ttl: Integer,
      ).void
    end
    def self.setup(job_status_id:, job_status_class:, issue_ids:, ttl: DEFAULT_TTL)
      return if issue_ids.empty?

      r = redis
      count_key = "#{REDIS_KEY_PREFIX}:count:#{job_status_id}"
      r.set(count_key, issue_ids.size, ex: ttl)

      meta_key = "#{REDIS_KEY_PREFIX}:meta:#{job_status_id}"
      r.set(meta_key, job_status_class, ex: ttl)

      issue_ids.each do |issue_id|
        awaiting_key = "#{REDIS_KEY_PREFIX}:awaiting:issue:#{issue_id}"
        r.sadd(awaiting_key, job_status_id)
        r.expire(awaiting_key, ttl)
      end
    end

    # Called by AddToSearchIndexJob after indexing. Decrements the counter;
    # when it reaches 0, finalizes the JobStatus.
    sig { params(document_type: String, document_id: T.untyped).void }
    def self.on_index_complete(document_type, document_id)
      return unless document_type == "issue"

      r = redis
      awaiting_key = "#{REDIS_KEY_PREFIX}:awaiting:issue:#{document_id}"

      job_status_ids = r.smembers(awaiting_key)
      return if job_status_ids.nil? || job_status_ids.empty?

      GitHub.logger.info(
        "Bulk index coordination: on_index_complete called",
        "document_id" => document_id,
        "awaiting_job_status_ids" => job_status_ids.join(","),
      )

      job_status_ids.each do |job_status_id|
        # SREM is atomic — only the first job for this issue decrements the counter
        removed = r.srem(awaiting_key, job_status_id)
        unless removed_successfully?(removed)
          GitHub.logger.info(
            "Bulk index coordination: SREM no-op (already removed)",
            "document_id" => document_id,
            "job_status_id" => job_status_id,
          )
          next
        end

        count_key = "#{REDIS_KEY_PREFIX}:count:#{job_status_id}"
        # Guard: if the key expired or was already cleaned up, skip to avoid creating a stale key at -1
        unless r.exists?(count_key)
          GitHub.logger.warn(
            "Bulk index coordination: count key missing (expired?)",
            "document_id" => document_id,
            "job_status_id" => job_status_id,
          )
          next
        end

        remaining = r.decr(count_key)

        GitHub.logger.info(
          "Bulk index coordination: decremented",
          "document_id" => document_id,
          "job_status_id" => job_status_id,
          "remaining" => remaining,
        )

        if remaining <= 0
          finalize_job_status(job_status_id)
        end
      end
    rescue => e
      GitHub.logger.error(
        "Bulk index coordination failed",
        "error" => e.message,
        "error_class" => e.class.name,
        "document_type" => document_type,
        "document_id" => document_id,
      )
    end

    sig { params(job_status_id: String).void }
    def self.finalize_job_status(job_status_id)
      r = redis
      meta_key = "#{REDIS_KEY_PREFIX}:meta:#{job_status_id}"
      count_key = "#{REDIS_KEY_PREFIX}:count:#{job_status_id}"
      job_status_class = r.get(meta_key)
      return unless job_status_class

      unless ALLOWED_JOB_STATUS_CLASSES.include?(job_status_class)
        GitHub.logger.error(
          "Bulk index coordination: unexpected job status class",
          "job_status_class" => job_status_class,
          "job_status_id" => job_status_id,
        )
        return
      end

      # Wait for ES refresh cycle before signaling success
      sleep(ES_REFRESH_INTERVAL)

      status = job_status_class.safe_constantize&.find(job_status_id)
      if status
        status.success!

        GitHub.logger.info(
          "Bulk index coordination finalized job status",
          "job_status_id" => job_status_id,
          "job_status_class" => job_status_class,
        )
      end
    rescue => e
      GitHub.logger.error(
        "Failed to finalize bulk index job status",
        "error" => e.message,
        "error_class" => e.class.name,
        "job_status_id" => job_status_id,
      )
    ensure
      r&.del(meta_key) if meta_key
      r&.del(count_key) if count_key
    end

    # Redis SREM returns Integer (>= redis-rb 4.8) or Boolean (older versions)
    sig { params(result: T.untyped).returns(T::Boolean) }
    def self.removed_successfully?(result)
      result.is_a?(Integer) ? result > 0 : !!result
    end

    private_class_method :finalize_job_status, :removed_successfully?
  end
end
