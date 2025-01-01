# typed: strict
# frozen_string_literal: true

# This job identifies orphaned repositories and enqueues a separate job for each repository to delete orphaned data.
#
# The job can be scheduled to run periodically or triggered manually with the following configurable parameters:
# - `limit`: The maximum number of repositories to process across all batches (default: 1_000_000).
# - `batch_size`: The number of repositories to process in each batch (default: 1000).
# - `source`: The origin or context that initiated the job (default: "unknown").
# - `dry_run`: A flag to indicate whether the job should run in dry-run mode, skipping the actual disablement of repositories (default: true).
# - `offset_item_id`: A repository ID to be used as a cursor in the `where id > ?` clause (default: 0).
# - `progress`: The current progress of the job, representing the number of repositories processed so far (default: 0).
#
# Example usage:
#   FindOrphanedReposJob.perform_later(limit: 1000, batch_size: 100, source: "manual", dry_run: true)
#
module DependencyGraph
  class FindOrphanedReposJob < BaseFindReposJob

    queue_as :dependency_graph_find_inactive_repos

    retry_on_dirty_exit

    # The key used for the Redis mutex to prevent concurrent execution of this job.
    MUTEX_KEY = "dg:find_orphaned_repos"

    # Prefix for metrics related to this job.
    METRICS_PREFIX = "dependency_graph.jobs.find_orphaned_repos"

    # This feature flag is used to determine if data for orphaned repositories may be deleted.
    ALLOW_DELETION_ORPHANED_REPO_FLAG = "dependency_graph_allow_deletion_of_orphaned_repos"

    # The size of the batch to be processed in bulk enqueue mode.
    BULK_ENQUEUE_SIZE = 1000

    # If any of the below job queue is being throttled, delay the entire batch.
    sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
    def fanout_jobs
      [DeleteOrphanRepositoryJob]
    end

    # Find the next batch of orphaned repositories to be processed.
    #
    # offset_item_id - an id of the record to be used as the first one for the current batch in `where id > ?` clause.
    # progress - the current progress of the job, updated and supplied by BatchedJob
    # **options - will contain all remaining params that were passed to Job.perform_later(options) call
    #
    # Returns an array of orphaned repository IDs
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

      # report the total number of orphaned repositories if this is the first batch
      if progress == 0
        count_query = Queries::Trino::ReposWithOrphanedManifestsCount.new
        count = count_query.run_query.flatten.first
        GitHub.dogstats.distribution("#{METRICS_PREFIX}.orphaned_repos.count", count, tags: all_stats_tags)
        GitHub.logger.info("Orphaned repositories count complete", logging_context.merge("count" => count))
        if count.nil? || count.zero?
          GitHub.dogstats.increment("#{METRICS_PREFIX}.skipped", tags: all_stats_tags + ["cause:no_orphaned_repos"])
          GitHub.logger.info("No orphaned repositories found", logging_context)
          return []
        end
      end

      # find the next batch of orphaned repositories
      query = Queries::Trino::ReposWithOrphanedManifests.new(
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

    # Enqueues a separate job for each orphan repository to be cleaned.
    #
    # repository_ids - the list of ids to be processed
    # dry_run - whether to run the job in dry run mode to skip enqueuing the delete job
    # **options - will contain all remaining params that were passed to Job.perform_later(options) call
    #
    sig { override.params(repository_ids: T::Array[Integer], dry_run: T::Boolean, options: T.untyped).void }
    def process_batch(repository_ids, dry_run: self.dry_run, **options)
      return if repository_ids.empty?

      if dry_run
        GitHub.logger.info(
          "Would enqueue DeleteOrphanRepositoryJobs",
          logging_context.merge("jobs_count" => repository_ids.size))
        return
      end

      repository_ids.each_slice(BULK_ENQUEUE_SIZE) do |bulk|
        ActiveJob.perform_all_later(bulk.map do |repository_id|
          DeleteOrphanRepositoryJob.new(repository_id: repository_id, source: source)
        end)
        GitHub.dogstats.count("#{METRICS_PREFIX}.enqueued_fanout", bulk.size, tags: all_stats_tags)
      end
    end

    private

    # Only process the current batch and enqueue the next one if the feature flag is enabled for staff_user
    sig { override.returns(T::Boolean) }
    def job_enabled?
      return false if GitHub.enterprise?

      ::DependencyGraph.check_feature_for_user(User.staff_user, ALLOW_DELETION_ORPHANED_REPO_FLAG)
    end

    sig { override.void }
    def validate_additional_inputs
    end

    sig { override.returns(String) }
    def mutex_key
      MUTEX_KEY
    end
  end
end
