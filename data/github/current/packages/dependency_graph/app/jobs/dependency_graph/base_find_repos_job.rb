# typed: strict
# frozen_string_literal: true

# This is a base abstract job class for finding repositories to be processed.
#
# It leverages batched processing to handle repositories in manageable groups, where each batch is executed as a distinct job.
#
# The `BatchedJobThrottler` module introduces delays between batch enqueuing using feature flags, for example:
#   - `dependency_graph_find_orphaned_repos_job_wait_between_batches_factor`: Determines the wait time multiplier between batches.
#   - `dependency_graph_find_orphaned_repos_job_wait_jitter`: Adds randomness to the wait time to prevent predictable patterns.
#
# The `FanoutThrottler` ensures system stability by regulating job execution. Jobs are re-enqueued when queue depth thresholds,
#   calculated based on the batch size and a configurable multiplier (controlled via feature flags, for example:
#   `dependency_graph_find_orphaned_repos_job_fanout_multiplier`), are exceeded.
#
# The `RetryJob` provides robust retry logic for handling dirty exits and unhandled errors, ensuring reliable job execution.
#
# Note: To ensure proper behavior, `FanoutThrottler` is included before `RetryJob` in the job class.
#
module DependencyGraph
  class BaseFindReposJob < BatchedJob
    include BatchedJobThrottler
    include FanoutThrottler
    include RetryJob
    include GitHub::Memoizer
    extend T::Helpers

    abstract!

    DEFAULT_BATCH_SIZE = 1000
    DEFAULT_LIMIT = 1_000_000
    DEFAULT_SOURCE = "unknown"
    DEFAULT_DRY_RUN = true

    # Returns an array of job classes that are subject to throttling.
    #
    # Optionally override to return an array of job classes that should be throttled.
    #
    sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
    def fanout_jobs
      []
    end

    # Uses the batch size to calculate the allowed queue depth for fanout queues.
    # allowed_queue_depth = batch_size * multiplier (default: 1 - configurable using ff)
    sig { returns(Integer) }
    def fanout_depth
      batch_size
    end

    # Abstract method to find the next batch of repositories to be processed.
    #
    # Override to implement the logic for fetching the next batch of repositories.
    #
    # offset_item_id - an id of the record to be used as the first one for the current batch in `where id > ?` clause.
    # progress - the current progress of the job, updated and supplied by BatchedJob
    # **options - will contain all remaining params that were passed to Job.perform_later(options) call
    #
    # Returns an array of repository IDs
    #
    sig do
      abstract.params(
      offset_item_id: Integer,
      progress: Integer,
      options: T.untyped,
      ).returns(T::Array[Integer])
    end
    def next_batch(offset_item_id:, progress: self.progress, **options); end

    # Abstract method to process a batch of repositories.
    #
    # Override to implement the logic for processing a batch of repositories.
    #
    # repository_ids - the list of ids to be processed
    # dry_run - whether to run the job in dry run mode
    # **options - will contain all remaining params that were passed to Job.perform_later(options) call
    #
    sig { abstract.params(repository_ids: T::Array[Integer], dry_run: T::Boolean, options: T.untyped).void }
    def process_batch(repository_ids, dry_run: self.dry_run, **options); end

    # Finalizes the batch processing.
    #
    # repository_ids - the list of ids that were processed in the batch
    # progress - the current progress of the job, updated and supplied by the parent class
    # **options - will contain all remaining params that were passed to Job.perform_later(options) call
    #
    sig { override.params(repository_ids: T::Array[Integer], progress: Integer, options: T.untyped).void }
    def finalize_batch(repository_ids, progress:, **options)
      # Release the lock if we hold it, otherwise we are a duplicate process that should no-op.
      return unless mutex.unlock

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
      job_enabled? &&
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

    # Ensure we release the lock in the event of an exception that prevents us reaching `finalize_batch`
    #
    # finished_successfully - boolean indicating whether the job processed cleanly or not
    # **options - will contain all remaining params that were passed to Job.perform_later(options) call
    #
    sig { override.params(finished_successfully: T::Boolean, options: T.untyped).void }
    def ensure_perform(finished_successfully:, **options)
      mutex.unlock
    end

    # Ensure we release the lock in the event of an exception that is caught by the retry logic.
    #
    sig { override.void }
    def ensure_execute
      mutex.unlock
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

    # Method to determine if the job is enabled.
    #
    # Optionally override this method to control whether the job should run. A good example is to check a feature flag.
    #
    sig { returns(T::Boolean) }
    def job_enabled?
      true
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

      validate_additional_inputs
    end

    # Method to validate additional inputs specific to the inheriting job.
    #
    # Override this method in the inheriting job class to add custom validation logic for additional inputs.
    #
    sig { void }
    def validate_additional_inputs
    end

    sig { returns(T::Boolean) }
    memoize def dry_run
      (arguments[0] || {}).fetch(:dry_run, DEFAULT_DRY_RUN)
    end

    sig { returns(String) }
    memoize def source
      (arguments[0] || {}).fetch(:source, DEFAULT_SOURCE)
    end

    sig { returns(Integer) }
    memoize def batch_size
      (arguments[0] || {}).fetch(:batch_size, DEFAULT_BATCH_SIZE)
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

    sig { returns(GitHub::Redis::Mutex) }
    memoize def mutex
      GitHub::Redis::Mutex.new(
        "#{mutex_key}:#{source}",
        timeout: 5.minutes,
      )
    end

    # Returns a unique key for the mutex used by this job.
    #
    # Override this method in the inheriting job class to provide a unique key for the mutex.
    #
    # Returns a string representing the mutex key.
    #
    sig { abstract.returns(String) }
    def mutex_key; end
  end
end
