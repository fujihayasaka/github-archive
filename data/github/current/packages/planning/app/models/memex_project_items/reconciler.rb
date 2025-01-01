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

    # Telemetry from the data linked below suggests that this is the size of project (in terms of number of
    # items) that we can reconcile within roughly 30 seconds. We use that as our target batch size for each instance
    # of this class (hence also for each instance of `RepairMemexProjectItemsIndexJob`) so that we stay within the
    # recommended runtime of of 60 seconds per job instance.
    #
    # If we find that the repair job starts to get killed more frequently, then we should tune this value based on
    # telemetry from a more recent time window.
    #
    # https://app.datadoghq.com/dashboard/dk4-uth-4dw/memex-repairreconcilation?from_ts=1750964400000&to_ts=1751029200000&live=false&tile_focus=4258972487448234
    RECONCILER_BATCH_ITEM_LIMIT = 10_000

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

    # Whether to force an update for all item documents, regardless of computed diff.
    attr_reader :force_update

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
      @force_update = opts.fetch(:force_update, false)

      Failbot.push(
        "gh.memex.items_elasticsearch_repair.attempt" => @attempt,
        "gh.memex.items_elasticsearch_repair.job_id" => @reconcile_id,
        "gh.memex.items_elasticsearch_repair.group_key" => @group_key,
        "gh.memex.items_elasticsearch_repair.reconciler_batch_key" => @reconciler_batch_key,
      )
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
    sig do
      params(
        # Surprisingly, `Aqueduct::Worker::JobKilled` does not inherit from `StandardError`.
        exception: T.any(Aqueduct::Worker::JobKilled, StandardError)
      ).void
    end
    def failed!(exception)
      unreconciled_memex_project_ids = store_unreconciled_batch
      increment_stats(error_key, unreconciled_memex_project_ids&.length || 1)
      redis.sadd(failed_reconciler_batches_key, reconciler_batch_key)
      redis.srem(reconciler_batches_key, reconciler_batch_key)
    ensure
      Failbot.report(
        exception,
        "code.namespace": self.class.name,
        "code.function": "failed!",
        "elasticsearch.index": index.name,
        "gh.memex.reconciler.failed": true
      )
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
      project_ids = mutex.lock do
        GitHub.dogstats.time "memex_project.reconciler.prepare_batch", tags: ["index:#{index.name}"] do
          binds = {
            last_memex_project_id: get_offset,
            limit: Arel.sql(RECONCILER_BATCH_ITEM_LIMIT.to_s),
          }

          rows = MemexProject.connection.select_rows(Arel.sql(<<-SQL, **binds))
            SELECT
              projects.id
            FROM
              memex_projects AS projects
            LEFT JOIN
              memex_project_items AS items
            ON
              projects.id = items.memex_project_id
            WHERE
              projects.id > :last_memex_project_id
            ORDER BY
              projects.id ASC
            LIMIT
              :limit
          SQL

          memex_project_ids = rows.map(&:first).uniq

          # If we've retrieved more than one project and we've also filled the page size, then we can't be sure that
          # we've retrieved all items for the last project in the list. In that case, we drop that last project so
          # that we ensure that the remaining projects are all within our target item limit (and hence that the batch
          # size we operate on is small enough).
          #
          # On the other hand, if we've retrieved only one project or we've finished paging through all items, then
          # we have no choice but to attempt reconciliation of all remaining projects.
          memex_project_ids.pop if memex_project_ids.length > 1 && rows.length == RECONCILER_BATCH_ITEM_LIMIT

          set_reconciler_batch(memex_project_ids)
          set_offset(memex_project_ids.last) if memex_project_ids.any?

          memex_project_ids
        end
      end

      GitHub.logger.info(
        "Computed new batch of project IDs for repair",
        {
          "code.namespace" => self.class.name,
          "code.function" => "calculate_reconciler_batch",
          "elasticsearch.index" => @index.name,
          "gh.memex.items_elasticsearch_repair.job_id" => reconcile_id,
          "gh.memex.items_elasticsearch_repair.batch.empty" => project_ids.empty?,
          "gh.memex.items_elasticsearch_repair.batch.min_id" => project_ids.first,
          "gh.memex.items_elasticsearch_repair.batch.max_id" => project_ids.last,
          "gh.memex.items_elasticsearch_repair.group_key" => group_key,
          "gh.memex.items_elasticsearch_repair.reconciler_batch_key" => reconciler_batch_key,
        }
      )

      project_ids
    end

    # The list of MemexProject IDs that have not been reconciled for the current batch.
    sig { returns(T::Array[Integer]) }
    def get_reconciler_batch
      project_ids = if (ids = redis.hget(group_key, reconciler_batch_key))
        GitHub::JSON.parse(ids)
      elsif retry_attempt?
        raise MissingReconcileBatchError, "Unable to find batch of MemexProjects to reconcile"
      else
        []
      end

      GitHub.logger.info(
        "Retrieved existing batch of project IDs for repair",
        {
          "code.namespace" => self.class.name,
          "code.function" => "get_reconciler_batch",
          "elasticsearch.index" => @index.name,
          "gh.memex.items_elasticsearch_repair.attempt" => attempt,
          "gh.memex.items_elasticsearch_repair.job_id" => reconcile_id,
          "gh.memex.items_elasticsearch_repair.batch.empty" => project_ids.empty?,
          "gh.memex.items_elasticsearch_repair.batch.min_id" => project_ids.first,
          "gh.memex.items_elasticsearch_repair.batch.max_id" => project_ids.last,
          "gh.memex.items_elasticsearch_repair.group_key" => group_key,
          "gh.memex.items_elasticsearch_repair.reconciler_batch_key" => reconciler_batch_key,
        }
      )

      project_ids
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

      MemexProject.where(id: reconciler_memex_project_ids).order(id: :asc).each do |memex_project|
        reconcile_memex_project(memex_project)
      end

      # Successfully repaired batch of IDs, can clear the batch.
      clear_reconcile_batch

      GitHub.logger.info(
        "Completed repair for batch of project IDs",
        {
          "code.namespace" => self.class.name,
          "code.function" => "reconcile",
          "elasticsearch.index" => @index.name,
          "gh.memex.items_elasticsearch_repair.attempt" => attempt,
          "gh.memex.items_elasticsearch_repair.job_id" => reconcile_id,
          "gh.memex.items_elasticsearch_repair.batch.empty" => reconciler_memex_project_ids.empty?,
          "gh.memex.items_elasticsearch_repair.batch.min_id" => reconciler_memex_project_ids.first,
          "gh.memex.items_elasticsearch_repair.batch.max_id" => reconciler_memex_project_ids.last,
          "gh.memex.items_elasticsearch_repair.group_key" => group_key,
          "gh.memex.items_elasticsearch_repair.reconciler_batch_key" => reconciler_batch_key,
        }
      )
    rescue GitHub::Redis::Mutex::LockError => boom
      GitHub.dogstats.increment("search.repair.lock_error", tags: ["index:#{index.name}"])
      # Could not acquire lock, next worker will try acquiring a lock to generate next batch of projects to reconcile.
      nil
    rescue StandardError => boom # rubocop:todo Lint/RescueException
      store_unreconciled_batch
      Failbot.report(
        boom,
        "code.namespace": self.class.name,
        "code.function": "reconcile",
        "elasticsearch.index": index.name,
        "gh.memex.reconciler.failed": false
      )
      raise
    end

    private

    # Store and return the batch of MemexProject IDs that have not been reconciled yet.
    sig { returns(T.nilable(T::Array[Integer])) }
    def store_unreconciled_batch
      unreconciled_memex_project_ids = reconciler_memex_project_ids - @reconciled_memex_project_ids.to_a

      GitHub.dogstats.count "memex_project.reconciler.batch.store", unreconciled_memex_project_ids.length, tags: ["index:#{index.name}"]
      set_reconciler_batch(unreconciled_memex_project_ids)

      unreconciled_memex_project_ids
    rescue MissingReconcileBatchError
      GitHub.logger.info(
        "Failed to store batch of project IDs for later retry",
        {
          "code.namespace" => self.class.name,
          "code.function" => "store_unreconciled_batch",
          "elasticsearch.index" => @index.name,
          "gh.memex.items_elasticsearch_repair.attempt" => attempt,
          "gh.memex.items_elasticsearch_repair.job_id" => reconcile_id,
          "gh.memex.items_elasticsearch_repair.group_key" => group_key,
          "gh.memex.items_elasticsearch_repair.reconciler_batch_key" => reconciler_batch_key,
        }
      )

      nil
    end

    sig { params(ids: T::Array[Integer]).void }
    def set_reconciler_batch(ids)
      redis.hset(group_key, reconciler_batch_key, GitHub::JSON.encode(ids))
      redis.sadd(reconciler_batches_key, reconciler_batch_key)
    end

    # Clear the stored batch of MemexProjects needing to be reconciled.
    sig { void }
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
        reconciler = Search::MemexProjectItemReconciler.new(T.must(memex_project.id), live_updates: false, read_only: false, force_update:, index:)

        memex_project.memex_project_items.order(id: :asc).in_batches(of: MEMEX_PROJECT_ITEM_BATCH_SIZE) do |batch|
          memex_project_items = batch.to_a
          result = reconciler.reconcile!(memex_project_items)
          last_reconciled_item_id = T.cast(memex_project_items.last&.id, Integer)

          read_count += memex_project_items.length
          added_count += result.added
          updated_count += result.updated
          removed_count += result.removed
          errored_count += result.errored
        end

        # We just processed the last batch, so clear any items left in Elasticsearch with a higher ID.
        greater_than_or_equal_to_item_id = last_reconciled_item_id + 1 # Add one to make sure we don't remove the last thing we successfully re-synced.
        result = reconciler.clear!(greater_than_or_equal_to_item_id:)
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
      memex_project_id = T.must(memex_project.id)
      consistency_record = MemexProjectElasticsearchConsistency.find_or_initialize_by(memex_project_id:, index_name: index.name)
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

      unless consistency_record.consistent?
        GitHub.logger.info(
          "Elasticsearch index repair failed for a project",
          {
            "code.namespace" => self.class.name,
            "code.function" => "track_consistency",
            "elasticsearch.index" => @index.name,
            "gh.memex.inconsistency_threshold" => MemexProjectElasticsearchConsistency::INCONSISTENCY_THRESHOLD,
            "gh.memex.items_elasticsearch_repair.attempt" => attempt,
            "gh.memex.items_elasticsearch_repair.job_id" => reconcile_id,
            "gh.memex.items_elasticsearch_repair.group_key" => group_key,
            "gh.memex.items_elasticsearch_repair.reconciler_batch_key" => reconciler_batch_key,
            "gh.memex.project.id" => memex_project_id,
            "gh.memex.project.consistency" => consistency,
          }
        )
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
