# typed: strict
# frozen_string_literal: true

# This job identifies inactive repositories and enqueues a separate job for each repository to disable it.
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
module DependencyGraph
  class FindInactiveReposJob < BaseFindReposJob

    queue_as :dependency_graph_find_inactive_repos

    retry_on_dirty_exit

    DEFAULT_MAX_STARS = 1
    DEFAULT_MAX_YEARS = 10
    DEFAULT_SKIP_ENTERPRISE = true

    # The key used for the Redis mutex to prevent concurrent execution of this job.
    MUTEX_KEY = "dg:find_inactive_repos"

    # Prefix for metrics related to this job.
    METRICS_PREFIX = "dependency_graph.jobs.find_inactive_repos"

    # This feature flag is used to determine if inactive repositories may be disabled.
    ALLOW_DISABLE_INACTIVE_REPO_FLAG = "dependency_graph_allow_disable_of_inactive_repos"

    # The size of the batch to be processed in bulk enqueue mode.
    BULK_ENQUEUE_SIZE = 1000

    # If any of the below job queue is being throttled, delay the entire batch.
    sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
    def fanout_jobs
      [DisableRepositoryJob]
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
      unless job_enabled?
        GitHub.dogstats.increment("#{METRICS_PREFIX}.skipped", tags: all_stats_tags + ["cause:flag_disabled"])
        GitHub.logger.info("Feature flag is disabled for staff user", logging_context)
        return []
      end

      unless mutex.try_lock
        GitHub.dogstats.increment("#{METRICS_PREFIX}.skipped", tags: all_stats_tags + ["cause:job_lock"])
        GitHub.logger.info("Cannot obtain the job lock", logging_context)
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

      if dry_run
        GitHub.logger.info(
          "Would enqueue DisableRepositoryJobs",
          logging_context.merge("jobs_count" => repository_ids.size))
        return
      end

      repository_ids.each_slice(BULK_ENQUEUE_SIZE) do |bulk|
        ActiveJob.perform_all_later(bulk.map do |repository_id|
          DisableRepositoryJob.new(repository_id: repository_id, source: source)
        end)
        GitHub.dogstats.count("#{METRICS_PREFIX}.enqueued_fanout", bulk.size, tags: all_stats_tags)
      end
    end

    protected

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "job.max_stars" => max_stars,
        "job.max_years" => max_years,
        "job.skip_enterprise" => skip_enterprise,
      })
    end

    private

    # Only process the current batch and enqueue the next one if the feature flag is enabled for staff_user
    sig { override.returns(T::Boolean) }
    def job_enabled?
      return false if GitHub.enterprise?

      ::DependencyGraph.check_feature_for_user(User.staff_user, ALLOW_DISABLE_INACTIVE_REPO_FLAG)
    end

    sig { override.void }
    def validate_additional_inputs
      # We don't want to accidenally delete data for active repositories
      if max_years < 3
        raise ArgumentError, "Max years must be 3 or greater"
      end

      # Max stars equal 1 is equivalent to no stars
      if max_stars < 1
        raise ArgumentError, "Max stars must be 1 or greater"
      end
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

    sig { override.returns(String) }
    def mutex_key
      MUTEX_KEY
    end
  end
end
