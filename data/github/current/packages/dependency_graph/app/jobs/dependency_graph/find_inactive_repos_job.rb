# typed: strict
# frozen_string_literal: true

# This job identifies inactive repositories and enqueues a separate job for each repository to disable it.
#
# It leverages batched processing to handle repositories in manageable groups, where each batch is executed as a distinct job.
#
# The job can be scheduled to run periodically or triggered manually with the following configurable parameters:
# - `limit`: The maximum number of repositories to process across all batches (default: 1_000_000).
# - `batch_size`: The number of repositories to process in each batch (default: 1000).
# - `max_stars`: The maximum number of stars a repository can have to qualify as inactive (default: 1).
# - `max_years`: The maximum number of years since the last activity for a repository to qualify as inactive (default: 10).
# - `skip_enterprise`: A flag to skip processing repositories owned by enterprise accounts (default: true).
# - `source`: The origin or context that initiated the job (default: "unknown").
# - `dry_run`: A flag to indicate whether the job should run in dry-run mode, skipping the actual disablement of repositories (default: true).
# - `offset_item_id`: A repository ID to be used as a cursor in the `where id > ?` clause (default: 0).
# - `progress`: The current progress of the job, representing the number of repositories processed so far (default: 0).
#
# Example usage:
#   FindInactiveReposJob.perform_later(limit: 1000, batch_size: 100, max_stars: 10, max_years: 3, source: "manual", dry_run: true)
#
# The `BatchedJobThrottler` module introduces delays between batch enqueuing using feature flags:
#   - `dependency_graph_find_inactive_repos_job_wait_between_batches_factor`: Determines the wait time multiplier between batches.
#   - `dependency_graph_find_inactive_repos_job_wait_jitter`: Adds randomness to the wait time to prevent predictable patterns.
#
# The `FanoutThrottler` and `RetryJob` modules enhance job execution with the following mechanisms:
# - `FanoutThrottler`: Ensures system stability by regulating job execution. Jobs are re-enqueued when queue depth thresholds,
#   calculated based on the batch size and a configurable multiplier (controlled via the feature flag
#   `dependency_graph_find_inactive_repos_job_fanout_multiplier`), are exceeded.
# - `RetryJob`: Provides robust retry logic for handling dirty exits and unhandled errors, ensuring reliable job execution.
#
# Note: To ensure proper behavior, `FanoutThrottler` is included before `RetryJob` in the job class.
#
module DependencyGraph
  class FindInactiveReposJob < BatchedJob
    include BatchedJobThrottler
    include FanoutThrottler
    include RetryJob
    include GitHub::Memoizer

    queue_as :dependency_graph_find_inactive_repos

    retry_on_dirty_exit

    BATCH_SIZE = 1000
    DEFAULT_LIMIT = 1_000_000
    DEFAULT_MAX_STARS = 1
    DEFAULT_MAX_YEARS = 10
    DEFAULT_SKIP_ENTERPRISE = true
    DEFAULT_SOURCE = "unknown"
    DEFAULT_DRY_RUN = true

    # Prefix for metrics related to this job.
    METRICS_PREFIX = "dependency_graph.jobs.find_inactive_repos"

    # This feature flag is used to determine if inactive repositories may be disabled.
    ALLOW_DISABLE_INACTIVE_REPO_FLAG = "dependency_graph_allow_disable_of_inactive_repos"

    # If any of the below job queue is being throttled, delay the entire batch.
    sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
    def fanout_jobs
      [DisableRepositoryJob]
    end

    # Uses the batch size to calculate the allowed queue depth for fanout queues.
    # allowed_queue_depth = batch_size * multiplier (default: 1 - configurable using ff)
    sig { returns(Integer) }
    def fanout_depth
      batch_size
    end

    # Find the next batch of inactive repositories to be processed.
    #
    # offset_item_id - an id of the record to be used as the first one for the current batch in `where id > ?` clause.
    # progress - the current progress of the job, updated and supplied by BatchedJob
    # **options - will contain all remaining params that were passed to Job.perform_later(options) call
    #
    # Returns an array of inactive repository IDs
    #
    sig do
      override.params(
        offset_item_id: Integer,
        progress: Integer,
        options: T.untyped,
      )
      .returns(T::Array[Integer])
    end
    def next_batch(offset_item_id:, progress: self.progress, **options)
      unless disablement_allowed?
        GitHub.dogstats.increment("#{METRICS_PREFIX}.skipped", tags: all_stats_tags + ["cause:flag_disabled"])
        GitHub.logger.info("Feature flag is disabled for ghost user", logging_context)
        return []
      end

      GitHub.logger.info(
        "Starting to process new batch",
        logging_context.merge("job.progress" => progress, "job.offset_item_id" => offset_item_id)
      )

      validate_query_inputs

      # report the total number of inactive repositories if this is the first batch
      if progress == 0
        count_query = Queries::Trino::InactiveReposCount.new(
          max_stars: max_stars,
          max_years: max_years,
          skip_enterprise: skip_enterprise
        )
        count = count_query.run_query.flatten.first
        GitHub.dogstats.distribution("#{METRICS_PREFIX}.inactive_repos.count", count,
          tags: all_stats_tags + [
            "max_years:#{max_years}",
            "max_stars:#{max_stars}",
            "skip_enterprise:#{skip_enterprise}"
          ]
        )
        GitHub.logger.info("Inactive repositories count complete", logging_context.merge("count" => count))
        if count.nil? || count.zero?
          GitHub.dogstats.increment("#{METRICS_PREFIX}.skipped", tags: all_stats_tags + ["cause:no_inactive_repos"])
          GitHub.logger.info("No inactive repositories found", logging_context)
          return []
        end
      end

      # find the next batch of inactive repositories
      query = Queries::Trino::InactiveRepos.new(
        max_stars: max_stars,
        max_years: max_years,
        skip_enterprise: skip_enterprise,
        cursor: offset_item_id,
        limit: [limit - progress, batch_size].min
      )

      # return falttened query results
      query.run_query.flatten
    rescue ArgumentError => error
      # Will not re-raise the error since we wouldn't want to retry the job incase of invalid inputs
      GitHub.logger.error("Invalid job parameters", logging_context.merge("error.message" => error.message))
      GitHub.dogstats.increment("#{METRICS_PREFIX}.skipped", tags: all_stats_tags + ["cause:argument_error"])
      []
    end

    # Enqueues a separate job for each repository to be disabled.
    #
    # repository_ids - the list of ids to be processed
    # dry_run - whether to run the job in dry run mode to skip enqueuing the disable job
    # **options - will contain all remaining params that were passed to Job.perform_later(options) call
    #
    sig { override.params(repository_ids: T::Array[Integer], dry_run: T::Boolean, options: T.untyped).void }
    def process_batch(repository_ids, dry_run: self.dry_run, **options)
      return if repository_ids.empty?

      repository_ids.each do |repository_id|
        if dry_run
          GitHub.logger.info("Would enqueue DisableRepositoryJob", logging_context.merge("gh.repo_id" => repository_id))
          next
        end

        DisableRepositoryJob.perform_later(repository_id: repository_id, source: source)
        GitHub.dogstats.increment("#{METRICS_PREFIX}.enqueued_fanout", tags: all_stats_tags)
      end
    end

    # Finalizes the batch processing.
    #
    # repository_ids - the list of ids that were processed in the batch
    # progress - the current progress of the job, updated and supplied by the parent class
    # **options - will contain all remaining params that were passed to Job.perform_later(options) call
    #
    sig { override.params(repository_ids: T::Array[Integer], progress: Integer, options: T.untyped).void }
    def finalize_batch(repository_ids, progress:, **options)
      GitHub.logger.info(
        "Batch finalized",
        logging_context.merge("job.progress" => progress, "job.next_offset_item_id" => repository_ids.max)
      )
    end

    # Checks whether there is another batch available for processing.
    #
    # repository_ids - the list of ids that were processed in the batch
    # limit - the maximum number of items to be processed in the job by all batches
    # progress - the current progress of the job, not updated yet
    # batch_size - the default batch size for the job, unless overridden
    # **options - will contain all remaining params that were passed to Job.perform_later(options) call
    #
    # Returns true if there is another batch available, false otherwise.
    #
    sig { override.params(repository_ids: T::Array[Integer], limit: Integer, progress: Integer, batch_size: Integer, options: T.untyped).returns(T::Boolean) }
    def has_next_batch?(repository_ids, limit: self.limit, progress: self.progress, batch_size: self.batch_size, **options)
      disablement_allowed? &&
      batch_size.positive? &&
      limit.positive? &&
      (progress + batch_size) < limit &&
      repository_ids.size >= batch_size
    end

    # Gets the offset_item_id (cursor), which will be the id before the first one in the next batch
    #
    # repository_ids - list of repository ids that were processed in the batch
    # **options - will contain all remaining params that were passed to Job.perform_later(options) call
    #
    # Returns the id of the last item in the batch
    #
    sig { override.params(repository_ids: T::Array[Integer], options: T.untyped).returns(Integer) }
    def next_batch_offset_item_id(repository_ids, **options)
      T.must(repository_ids.last)
    end

    protected

    sig { override.returns(T::Array[String]) }
    def stats_tags
      [
        "metric_type:dependency_graph",
        "source:#{source}"
      ].compact
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "job.limit" => limit,
        "job.batch_size" => batch_size,
        "job.max_stars" => max_stars,
        "job.max_years" => max_years,
        "job.skip_enterprise" => skip_enterprise,
        "job.source" => source,
        "job.dry_run" => dry_run,
        "job.queue" => queue_name,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "dependency_graph"
      })
    end

    private

    # Only process the current batch and enqueue the next one if the feature flag is enabled for ghost
    # This acts as a guardrail to prevent accidental disablement of active repositories
    sig { returns(T::Boolean) }
    def disablement_allowed?
      ::DependencyGraph.check_feature_for_user(User.ghost, ALLOW_DISABLE_INACTIVE_REPO_FLAG)
    end

    sig { void }
    def validate_query_inputs
      # What's the point?
      if batch_size <= 0
        raise ArgumentError, "Batch size must be greater than 0"
      end

      # What's the point?
      if limit <= 0
        raise ArgumentError, "Limit must be greater than 0"
      end

      # Can only happen if progress is greater than limit, in which case we would not have a next batch
      if [limit - progress, batch_size].min <= 0
        raise ArgumentError, "Query limit should be greater than 0"
      end

      # Repository IDs are non-negative integers
      if offset_item_id < 0
        raise ArgumentError, "Offset item ID must be a non-negative integer"
      end

      # We don't want to accidenally delete data for active repositories
      if max_years < 3
        raise ArgumentError, "Max years must be 3 or greater"
      end

      # Max stars equal 1 is equivalent to no stars
      if max_stars < 1
        raise ArgumentError, "Max stars must be 1 or greater"
      end
    end

    sig { returns(T::Boolean) }
    def dry_run
      (arguments[0] || {}).fetch(:dry_run, DEFAULT_DRY_RUN)
    end

    sig { returns(String) }
    def source
      (arguments[0] || {}).fetch(:source, DEFAULT_SOURCE)
    end

    sig { returns(Integer) }
    memoize def batch_size
      (arguments[0] || {}).fetch(:batch_size, BATCH_SIZE)
    end

    sig { returns(Integer) }
    memoize def limit
      (arguments[0] || {}).fetch(:limit, DEFAULT_LIMIT)
    end

    sig { returns(Integer) }
    memoize def progress
      (arguments[0] || {}).fetch(:progress, 0)
    end

    sig { returns(Integer) }
    memoize def offset_item_id
      (arguments[0] || {}).fetch(:offset_item_id, 0)
    end

    sig { returns(Integer) }
    memoize def max_stars
      (arguments[0] || {}).fetch(:max_stars, DEFAULT_MAX_STARS)
    end

    sig { returns(Integer) }
    memoize def max_years
      (arguments[0] || {}).fetch(:max_years, DEFAULT_MAX_YEARS)
    end

    sig { returns(T::Boolean) }
    memoize def skip_enterprise
      (arguments[0] || {}).fetch(:skip_enterprise, DEFAULT_SKIP_ENTERPRISE)
    end
  end
end
