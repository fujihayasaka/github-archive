# typed: true
# frozen_string_literal: true

module MemexProjectItems
  # MemexProjectItems::Reconciler is a custom reconcilation strategy used for performance reasons to iterate over
  # MemexProject records instead of the default MemexProjectItem records. This guarantees we reconcile a single
  # project at a time and can efficiently preload and cache column data necessary for the reconciliation process.
  #
  # This reconciler uses the reconcilation logic implemented in Search::MemexProjectItemReconciler compared to the
  # default Elastomer::Reconciler.
  class Reconciler < Elastomer::Reconciler
    include GitHub::Memoizer

    # Error raised when a batch of MemexProjects to reconcile is missing.
    class MissingReconcileBatchError < StandardError; end

    MEMEX_PROJECT_ITEM_BATCH_SIZE = 1000
    MEMEX_PROJECT_BATCH_SIZE = 100

    # Reconcile attempt number for a batch of MemexProjects.
    attr_reader :attempt

    # Unique ID to track the batch of MemexProjects to be reconciled.
    attr_reader :reconcile_id

    # Redis key to store the number of MemexProject records that have successfully been reconciled.
    attr_reader :memex_projects_reconciled_key

    # Redis key to store the list Redis keys pointing to batches of MemexProject IDs to reconcile.
    attr_reader :reconciler_batches_key

    # Redis key to store the list Redis keys pointing to batches of MemexProject IDs that could not be reconciled.
    attr_reader :failed_reconciler_batches_key

    # Redis key for the current batch of MemexProject IDs to be reconciled.
    attr_reader :reconciler_batch_key

    # List of MemexProject IDs that have been successfully reconciled during the current reconcile attempt.
    attr_reader :reconciled_memex_project_ids

    # Represents the result of a `reconcile_memex_project` operation.
    class ReconcileResult < T::Struct
      # The total number of items that were added, updated, or removed during the operation.
      const :reconciled_count, Integer

      # The total number of items that were iterated on during the operation.
      const :total_count, Integer

      # The number of Elasticsearch errors encountered during the operation.
      const :errored_count, Integer
    end

    def initialize(opts)
      super(
        opts.reverse_merge(
          type: "memex_project_item",
          limit: MEMEX_PROJECT_BATCH_SIZE,
          raise_errors: true,
          model_class: MemexProject,
        )
      )

      @reconcile_id = opts.fetch(:reconcile_id)
      @attempt = opts.fetch(:attempt)
      @memex_projects_reconciled_key = "#@type/memex_projects_reconciled"
      @reconciler_batches_key = "#@type/reconciler_batches"
      @failed_reconciler_batches_key = "#@type/failed_reconciler_batches"
      @reconciler_batch_key = "#@type/reconciler_batch/#{@reconcile_id}"
      @reconciled_memex_project_ids = Set.new
      @primary_index = @index.get_config.primary
    end

    sig { returns(T::Boolean) }
    def primary_index?
      @primary_index
    end

    # Number of projects that have been reconciled
    sig { returns(Integer) }
    def memex_projects_reconciled_count
      redis.hget(group_key, memex_projects_reconciled_key).to_i
    end

    # Mark the current batch of MemexProjects as failed to be reconciled and report the underlying error to Failbot.
    # The failed batch will be stored in Redis to be retried manually.
    sig { params(exception: StandardError).void }
    def failed!(exception)
      store_unreconciled_batch
      increment_stats(error_key, get_reconciler_batch.length)
      redis.sadd(failed_reconciler_batches_key, reconciler_batch_key)
      redis.srem(reconciler_batches_key, reconciler_batch_key)
      Failbot.report(exception.with_redacting!, "gh.memex.reconciler.failed": true)
      GitHub.dogstats.increment "memex_project.reconciler.batch.failed", tags: ["index:#{index.name}"]
    end

    # Determines if the reconciler has iterated over all eligible MemexProjects to be reconciled.
    sig { returns(T::Boolean) }
    def finished?
      # When all eligible MemexProjects have been iterated on and have had their batches prepared, the reconciler
      # marks itself as finished. In the event of retries, we want to ignore the global finished state and continue
      # to process the remaining MemexProjects from the current batch.
      return false if retry_attempt?
      super
    end

    sig { returns(MemexProjectItems::Reconciler) }
    def reset!
      redis.del(reconciler_batches_key)
      redis.del(failed_reconciler_batches_key)
      super
    end

    # Determines if this is a retry attempt for the current batch of MemexProjects.
    sig { returns(T::Boolean) }
    def retry_attempt?
      attempt > 1
    end

    # Returns the batch of MemexProject ids to reconcile. If this is the first execution for a given batch,
    # the reconciler will determine the next batch of MemexProjects to reconcile based on the offset stored by the
    # reconciler. If there was an exception raised during the initial attempt of reconciling a batch of MemexProjects,
    # the previous batch will be loaded.
    sig { returns(T::Array[Integer]) }
    memoize def reconciler_memex_project_ids
      if retry_attempt?
        get_reconciler_batch
      else
        calculate_reconciler_batch
      end
    end

    sig { returns(T::Array[Integer]) }
    def calculate_reconciler_batch
      # Obtain an exclusive lock across all repair workers for the index being repaired so additional workers do not
      # calculate the list of MemexProjects from the same offset as another worker. If an exception is raised the lock
      # is released.
      mutex.lock do
        GitHub.dogstats.time "memex_project.reconciler.prepare_batch", tags: ["index:#{index.name}"] do
          last_memex_project_id = get_offset

          memex_project_ids = MemexProject.select(:id).where("id > ?", last_memex_project_id).order(id: :asc).limit(MEMEX_PROJECT_BATCH_SIZE).pluck(:id)

          set_reconciler_batch(memex_project_ids)
          set_offset(memex_project_ids.last)

          memex_project_ids
        end
      end
    end

    # The list of MemexProject IDs that have not been reconciled for the current batch.
    sig { returns(T::Array[Integer]) }
    def get_reconciler_batch
      if (ids = redis.hget(group_key, reconciler_batch_key))
        GitHub::JSON.parse(ids)
      elsif retry_attempt?
        raise MissingReconcileBatchError, "Unable to find batch of MemexProjects to reconcile"
      else
        []
      end
    end

    # The list of Redis keys storing batches of MemexProject IDs that have not been reconciled or in process of being
    # reconciled.
    sig { returns(T::Array[String]) }
    def reconciler_batches
      redis.smembers(reconciler_batches_key)
    end

    # The number of batches of MemexProject IDs that need to be reconciled.
    sig { returns(Integer) }
    def reconciler_batches_count
      redis.scard(reconciler_batches_key)
    end

    # The list of Redis keys storing batches of MemexProject IDs that have failed to be reconciled.
    sig { returns(T::Array[String]) }
    def failed_reconciler_batches
      redis.smembers(failed_reconciler_batches_key)
    end

    # The number of batches of MemexProject IDs that have failed to be reconciled.
    sig { returns(Integer) }
    def failed_reconciler_batches_count
      redis.scard(failed_reconciler_batches_key)
    end

    sig { void }
    def reconcile
      if reconciler_memex_project_ids.empty?
        clear_reconcile_batch
        return finish!
      end

      if retry_attempt?
        GitHub.dogstats.increment "memex_project.reconciler.batch.retry", tags: ["index:#{index.name}", "attempt:#{attempt}"]
      end

      # Using find preserves order of ids ensuring the offset does not skip any projects.
      memex_projects = MemexProject.where(id: reconciler_memex_project_ids)
      memex_projects.each do |memex_project|
        reconcile_memex_project(memex_project)
      end

      # Successfully repaired batch of IDs, can clear the batch.
      clear_reconcile_batch
    rescue GitHub::Redis::Mutex::LockError => boom
      GitHub.dogstats.increment("search.repair.lock_error", tags: ["index:#{index.name}"])
      # Could not acquire lock, next worker will try acquiring a lock to generate next batch of projects to reconcile.
      nil
    rescue StandardError => boom # rubocop:todo Lint/GenericRescue
      store_unreconciled_batch
      Failbot.report(boom.with_redacting!, "gh.memex.reconciler.failed": false)
      raise
    end

    private

    # Store the batch of MemexProject IDs that have not been reconciled yet.
    sig { void }
    def store_unreconciled_batch
      unreconciled_memex_project_ids = reconciler_memex_project_ids - @reconciled_memex_project_ids.to_a
      GitHub.dogstats.count "memex_project.reconciler.batch.store", unreconciled_memex_project_ids.length, tags: ["index:#{index.name}"]
      set_reconciler_batch(unreconciled_memex_project_ids)
    end

    sig { params(ids: T::Array[Integer]).returns(T::Boolean) }
    def set_reconciler_batch(ids)
      redis.hset(group_key, reconciler_batch_key, GitHub::JSON.encode(ids))
      redis.sadd(reconciler_batches_key, reconciler_batch_key)
    end

    # Clear the stored batch of MemexProjects needing to be reconciled.
    sig { returns(T::Boolean) }
    def clear_reconcile_batch
      if retry_attempt?
        GitHub.dogstats.count "memex_project.reconciler.batch.reconciled", @reconciled_memex_project_ids.length, tags: ["index:#{index.name}"]
      end

      redis.hdel(group_key, reconciler_batch_key)
      redis.srem(reconciler_batches_key, reconciler_batch_key)
    end

    sig { params(memex_project: MemexProject).void }
    def reconcile_memex_project(memex_project)
      Failbot.push("gh.memex.project.id": memex_project.id)

      reconcile_started_at = Time.now
      read_count, added_count, updated_count, removed_count, errored_count = 0, 0, 0, 0, 0
      last_reconciled_item_id = 0

      track_consistency(memex_project) do
        reconciler = Search::MemexProjectItemReconciler.new(T.must(memex_project.id), live_updates: false, read_only: false, index:)

        memex_project.memex_project_items.order(id: :asc).in_batches(of: MEMEX_PROJECT_ITEM_BATCH_SIZE) do |batch|
          memex_project_items = batch.to_a
          result = reconciler.reconcile!(memex_project_items, wait_for_refresh: false)
          last_reconciled_item_id = T.cast(memex_project_items.last&.id, Integer)

          read_count += memex_project_items.length
          added_count += result.added
          updated_count += result.updated
          removed_count += result.removed
          errored_count += result.errored
        end

        # We just processed the last batch, so clear any items left in Elasticsearch with a higher ID.
        greater_than_or_equal_to_item_id = last_reconciled_item_id + 1 # Add one to make sure we don't remove the last thing we successfully re-synced.
        result = reconciler.clear!(greater_than_or_equal_to_item_id:, wait_for_refresh: false)
        added_count += result.added
        updated_count += result.updated
        removed_count += result.removed
        errored_count += result.errored

        ReconcileResult.new(
          reconciled_count: added_count + updated_count + removed_count,
          total_count: read_count + result.total,
          errored_count:,
        )
      end

      # Increment MemexProjectItem row level stats, this is used to observe the amount of rows operated on for items.
      increment_stats(add_key, added_count)
      increment_stats(update_key, updated_count)
      increment_stats(remove_key, removed_count)
      increment_stats(total_key, read_count)

      height_bucket = MemexPerformanceStatsHelper.bucketed_value(read_count, MemexPerformanceStatsHelper::MEMEX_WITHOUT_LIMITS_HEIGHT_BUCKETS)

      ms = ((Time.now - reconcile_started_at) * 1000).round
      GitHub.dogstats.timing "memex_project.reconcile", ms, tags: ["index:#{index.name}", "height_bucket:#{height_bucket}"]
      GitHub.dogstats.increment "memex_project.reconciled", tags: ["index:#{index.name}", "height_bucket:#{height_bucket}"]

      @reconciled_memex_project_ids << memex_project.id
      increment_stats(memex_projects_reconciled_key, 1)
    end

    sig { params(memex_project: MemexProject, block: T.proc.returns(ReconcileResult)).void }
    def track_consistency(memex_project, &block)
      if primary_index?
        memex_project_id = T.must(memex_project.id)
        consistency_record = MemexProjectElasticsearchConsistency.find_or_initialize_by(memex_project_id:)
        with_write { consistency_record.update!(repair_started_at: Time.now.utc) }
        reconcile_result = block.call
        consistency = MemexProjectElasticsearchConsistency.consistency_score(
          inconsistent_count: reconcile_result.errored_count,
          total_count: reconcile_result.total_count,
        )
        attributes = {
          repair_finished_at: Time.now.utc,
          evaluated_at: Time.now.utc,
          consistency:,
        }

        with_write { consistency_record.update(attributes) }
      else
        block.call
      end
    end

    def with_write(&block)
      ActiveRecord::Base.connected_to(role: :writing, &block)
    end

    # Use a custom wait time that the reconciler waits to obtain a lock to generate the next batch of MemexProjects to
    # reconcile to support a large amount of workers.
    def mutex
      @mutex ||= GitHub::Redis::MutexGroup.new(group_key, mutex_key, timeout: 60, wait: 30, sleep: 1)
    end
  end
end
