# typed: true
# frozen_string_literal: true

module MemexProjectItems
  # MemexProjectItems::Reconciler is a custom reconcilation strategy used for performance reasons to iterate over
  # MemexProject records instead of the default MemexProjectItem records. This guarantees we reconcile a single
  # project at a time and can efficiently preload and cache column data necessary for the reconciliation process.
  #
  # This reconciler uses the reconcilation logic implemented in Search::MemexProjectItemReconciler compared to the
  # default Elastomer::Reconciler. Only MemexProject records with the memex_table_without_limits feature flag enabled
  # are reconciled.
  class Reconciler < Elastomer::Reconciler
    extend T::Sig
    include GitHub::Memoizer

    # Error raised when a batch of MemexProjects to reconcile is missing.
    class MissingReconcileBatchError < StandardError; end

    MEMEX_PROJECT_ITEM_BATCH_SIZE = 1000
    MEMEX_PROJECT_BATCH_SIZE = 5

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

    def initialize(opts)
      super(
        opts.reverse_merge(
          type: "memex_project_item",
          limit: MEMEX_PROJECT_BATCH_SIZE,
          raise_errors: true,
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
      Failbot.report(exception.with_redacting!)
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

    # Progress reporting is calculated by comparing last MemexProject successfully repaired to the maximum number of
    # projects.
    sig { returns(Integer) }
    def last_id
      sorted_memex_project_without_limits_ids.last || 0
    end

    sig { returns(Float) }
    def progress
      return 0.0 unless (current_index = sorted_memex_project_without_limits_ids.index(get_offset))

      ((current_index + 1).to_f / sorted_memex_project_without_limits_ids.length) * 100
    end

    # Sorted set of MemexProject ids that have the memex_table_without_limits feature flag enabled to ensure
    # pagination is consistent.
    sig { returns(T::Array[Integer]) }
    memoize def sorted_memex_project_without_limits_ids
      # For development environments, reconcile all projects if MWL is globally enabled.
      return MemexProject.pluck(:id) if Rails.env.development? && GitHub.flipper[:memex_table_without_limits].enabled?

      MemexProject.memex_without_limits_beta_projects.sort
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
          pending_memex_project_ids = sorted_memex_project_without_limits_ids.drop_while do |id|
            id <= last_memex_project_id
          end

          pending_memex_project_ids.first(MEMEX_PROJECT_BATCH_SIZE).tap do |batch|
            set_reconciler_batch(batch)
            set_offset(batch.last)
          end
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
      Failbot.report(boom.with_redacting!)
      raise
    rescue StandardError => boom # rubocop:todo Lint/GenericRescue
      store_unreconciled_batch
      Failbot.report(boom.with_redacting!)
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
      reconcile_started_at = Time.now
      read_count, added_count, updated_count, removed_count = 0, 0, 0, 0
      last_reconciled_item_id = 0

      track_consistency(memex_project) do
        reconciler = Search::MemexProjectItemReconciler.new(T.must(memex_project.id), live_updates: false, read_only: false, index:)

        memex_project.memex_project_items.order(id: :asc).in_batches(of: MEMEX_PROJECT_ITEM_BATCH_SIZE) do |batch|
          memex_project_items = batch.to_a
          result = reconciler.reconcile!(memex_project_items, wait_for_refresh: false)
          last_reconciled_item_id = T.must(memex_project_items.last&.id)

          read_count += memex_project_items.length
          added_count += result.added
          updated_count += result.updated
          removed_count += result.removed
        end

        # We just processed the last batch, so clear any items left in Elasticsearch with a higher ID.
        greater_than_or_equal_to_item_id = last_reconciled_item_id + 1 # Add one to make sure we don't remove the last thing we successfully re-synced.
        result = reconciler.clear!(greater_than_or_equal_to_item_id:, wait_for_refresh: false)
        added_count += result.added
        updated_count += result.updated
        removed_count += result.removed

        consistency_reconciled_count = added_count + updated_count + removed_count
        consistency_total_count = read_count + result.total

        [consistency_reconciled_count, consistency_total_count]
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

    sig { params(memex_project: MemexProject, block: T.proc.returns(T::Array[Integer])).void }
    def track_consistency(memex_project, &block)
      if primary_index?
        consistency_record = with_write do
          MemexProjectElasticsearchConsistency.create_or_update(T.must(memex_project.id), repair_started_at: Time.now.utc)
        end
        reconciled_count, total_count = block.call
        attributes = {
          repair_finished_at: Time.now.utc,
        }
        if reconciled_count && total_count&.positive?
          consistency = MemexProjectElasticsearchConsistency.consistency_score(
            reconciled_count:,
            total_count:,
          )

          attributes[:consistency] = consistency
          attributes[:evaluated_at] = Time.now.utc
        end

        with_write { consistency_record.update(attributes) }
      else
        block.call
      end
    end

    def with_write(&block)
      ActiveRecord::Base.connected_to(role: :writing, &block)
    end
  end
end
