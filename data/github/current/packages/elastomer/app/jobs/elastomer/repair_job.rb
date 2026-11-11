# typed: true
# frozen_string_literal: true

module Elastomer
  # This superclass provides uniform functionality for all the search index
  # repair jobs as well as some nifty class-level helper methods to make
  # writing repair jobs super simple.
  #
  #   class RepairUsersIndex < ::Elastomer::RepairJob
  #     reconcile 'user',
  #       :fields => %w[updated_at],
  #       :limit  => 250,
  #       :reject => :spammy?
  #   end
  #
  # And to queue up one of these repair jobs, you give it the name of an
  # already existing index.
  #
  #   job = RepairUsersIndex.new 'users-3'
  #   job.enable.start(8)
  #
  # And now User models will be processed in batches of 250 at a time, and the
  # 'users-3' search index will be reconciled with the database. Eight workers
  # will be used in order to process the work in parallel.
  #
  # Issues and milestones live in the same search index, so we can reconcile
  # multiple ActiveRecord models in the same repair job.
  #
  #   class RepairIssuesIndexJob < Elastomer::RepairJob
  #     reconcile 'issue',
  #       :fields     => %w[updated_at state],
  #       :conditions => 'pull_request_id IS NULL',
  #       :include    => [:repository, :comments],
  #       :limit      => 100,
  #       :reject     => :spammy?
  #
  #     reconcile 'milestone'
  #       :fields => %w[updated_at state],
  #       :limit  => 100,
  #       :reject => :spammy?
  #   end
  #
  class RepairJob < ApplicationJob
    class InvalidRepairScopeError < StandardError; end
    include Elastomer::RedisMutexDependency

    queue_as :index_bulk
    retry_on_dirty_exit

    include GitHub::ServiceMapping

    ENABLED_KEY = "enabled"
    ELAPSED_KEY = "elapsed"
    STARTED_KEY = "started"
    ACTIVE_KEY  = "active"
    COMMITTED_KEY = "committed"
    WORKER_KEY = "workers"
    BATCH_SIZE_KEY = "batch_size"
    FINISHED_KEY = "finished_at"
    STRATEGY_KEY = "strategy"
    UPDATED_AT_START_KEY = "updated_after_start"
    UPPER_BOUND_KEY = "upper_bound"
    FORCE_REINDEX_KEY = "force_reindex"

    def to_partial_path
      "stafftools/search_indexes/repair_job"
    end

    class Strategy < T::Enum
      enums do
        # AllModels is a strategy that reconciles all index models.
        AllModels = new("all_models")

        # PartialBackfill is a strategy that reconciles index models that have been updated between a given date range.
        PartialBackfill = new("partial_backfill")
      end
    end

    # Start up one or more background jobs to perform the repair task.
    #
    # count - The number of background jobs to start.
    #
    # Returns `true` if this is the first call to start for this job.
    def start(count = 1)
      # Allows us to raise the error to users when a job is requested, so that
      # they don't have to wonder why a job isn't working.
      validate_target_scope!
      redis.hset(group_key, WORKER_KEY, count)
      redis.hsetnx(group_key, STARTED_KEY, Time.now.iso8601)
      redis.hsetnx(group_key, COMMITTED_KEY, 0)
      requeue_count = [0, count - redis.hget(group_key, ACTIVE_KEY).to_i].max
      requeue_count.times { requeue }

      GitHub.dogstats.event(
        "Repair Job started",
        "Repair job for index #{index_name} requested #{count} workers; spawned #{requeue_count} new workers",
        tags: datadog_tags(status: :info)
      )
    rescue Redis::BaseError => boom
      GitHub.dogstats.event(
        "Repair Job start error",
        "Repair job for group_key #{group_key} encountered Redis error on start: #{boom.message}",
        tags: datadog_tags(status: :error, error_class: boom.class.name)
      )
      raise
    end

    def setup_batch
      active_count = T.let(0, Integer)
      total_committed = T.let(0, Integer)

      GitHub.dogstats.increment("search.repair.batch_start", tags: datadog_tags)

      mutex(queue: :repair_job).lock do
        # If this worker was started by a requeue decision, we need to decrement the committed count.
        # Otherwise we leave it alone, since it was likely a fresh spawn.
        if redis.hget(group_key, COMMITTED_KEY).to_i > 0
          total_committed = redis.hincrby(group_key, COMMITTED_KEY, -1).to_i
        end
        active_count = T.let(redis.hincrby(group_key, ACTIVE_KEY, 1).to_i, Integer)
        true
      end
    rescue GitHub::Redis::Mutex::LockError
      requeue
      GitHub.dogstats.event(
        "Repair Job requeued due to lock contention",
        "Repair job batch for index #{index_name} could not start and was requeued due to lock contention. Active workers: #{active_count}, Total Committed Workers: #{total_committed}",
        tags: datadog_tags(status: :warn)
      )
      false
    ensure
      GitHub.dogstats.gauge("search.repair.workers.active", active_count, tags: datadog_tags)
    end

    def teardown_batch
      requeue_count = 0
      begin
        mutex(queue: :repair_job).lock do
          # Re-fetch requested count in case it was changed by user actions while working
          counts = redis.hmget(group_key, WORKER_KEY, ACTIVE_KEY, COMMITTED_KEY)
          requested_count = counts[0].to_i
          active_count = [counts[1].to_i - 1, 0].max
          committed_count = counts[2].to_i
          # Decrement active count since this worker is finishing up.
          # Fetch committed count so we don't reqeueue too many things.
          worker_capacity_remaining = T.let(requested_count - active_count - committed_count, Integer)
          should_requeue = enabled? && !finished? && worker_capacity_remaining.positive?

          requeue_count = should_requeue ? worker_capacity_remaining : 0

          redis.hset(group_key, ACTIVE_KEY, active_count, COMMITTED_KEY, committed_count + requeue_count)

          GitHub.dogstats.count("search.repair.workers.committed", committed_count, tags: datadog_tags)
          GitHub.dogstats.increment("search.repair.batch_complete", tags: datadog_tags(
            requeue: should_requeue,
            enabled: enabled?,
            finished: finished?,
          ))
        end
      rescue GitHub::Redis::Mutex::LockError
        # This case could slowly starve the queue, so we want to make sure we are aware of it happening
        # so we can pause/resume to mitigate if necessary.
        GitHub.dogstats.increment("search.repair.batch_complete", tags: datadog_tags(
          requeue:  :teardown_skipped_lock_contention,
          enabled: enabled?,
          finished: finished?,
        ))
      end

      requeue_count.times { requeue }

      GitHub.dogstats.count("search.repair.workers.requeued", requeue_count, tags: datadog_tags)
      GitHub.dogstats.gauge("search.repair.progress", progress, tags: datadog_tags)
      # Helps let us know if the job is getting slower, so we can monitor that.
      eta_countdown = [(estimated_completion_time.to_i - Time.now.to_i), 0].max
      GitHub.dogstats.gauge("search.repair.eta.seconds", eta_countdown, tags: datadog_tags)
    end

    # Perform the actual work of reconciling the search index with the canoncial
    # data source. This method will check the `enabled` flag and only perform
    # work if the flag is true. This method will enqueue another repair job
    # if there are more iterations to perform.
    #
    # Returns this repair job instance.
    def perform(name, opts = {})
      Search::SearchIndexingAutoThrottleDeciderJob.request_start
      validate_target_scope!

      # for contexts where the args provided to the instance
      # directly, use them. If not, ActiveJob::Base.arguments
      # captured at job instantiation (or, on the worker pool side,
      # in `job.deserialize(job_data)`) will be used to hydrate job
      # instance vars lazily on first uses in `job.repair!`
      if !name.blank?
        @index_name = name
        @job_opts = opts.with_indifferent_access
      end

      return if disabled?
      if setup_batch
        begin
          repair!
        ensure
          teardown_batch
        end
      end
    end

    # Perform the actual work of the repairing the search index. This method
    # will execute without checking the `enabled` flag. Only one iteration of
    # the repair job is performed.
    #
    # Use the `perform` method if you want to automatically enqueue another
    # repair job when this one completes. The `perform` method adheres to the
    # `enabled` semantics and will not perform work if the repair job has been
    # disabled.
    #
    # Returns this repair job instance.
    def repair!
      start = Time.now

      run_reconcilers = lambda {
        ActiveRecord::Base.connected_to(role: :reading) do
          reconcilers.each { |r| r.reconcile unless r.finished? }
        end
      }

      if GitHub.multi_tenant_enterprise?
        GitHub::CurrentTenant.unscope { run_reconcilers.call }
      else
        run_reconcilers.call
      end

      elapsed = Time.now - start
      redis.hincrbyfloat(group_key, ELAPSED_KEY, elapsed)

      GitHub.dogstats.timing("search.repair.elapsed", (elapsed * 1000).round(2), tags: datadog_tags)
      self
    rescue StandardError => boom
      Failbot.report(boom.with_redacting!)
      GitHub.dogstats.event(
        "Repair Job error",
        "Repair job with group_key #{group_key} encountered error",
        tags: datadog_tags(
          status: :error, error_class: boom.class.name, target_scope: target_scope, raise_errors: raise_errors?
        )
      )
      raise if raise_errors?
    end

    # Returns `true` if all the reconcilers report that they have finished
    # processing all models. Returns `false` if any reconciler has more models
    # to process.
    def finished?
      completed_at = redis.hget(group_key, FINISHED_KEY)&.to_f
      return true if completed_at&.positive?
      if reconcilers.all?(&:finished?)
        completed_at = Time.now.utc.to_f
        redis.hsetnx(group_key, FINISHED_KEY, completed_at)
        GitHub.dogstats.event(
          "Repair Job completed",
          "Repair job for index #{index_name} with group key #{group_key} marked complete",
          tags: datadog_tags(status: :info)
        )
      end
      completed_at&.positive? || false
    end

    # Returns the progress through the repair job - a floating point number
    # between 0.0 and 100.0.
    def progress
      return 0.0 unless exists?
      return 100.0 if finished?

      values = reconcilers.map { |r| r.progress }
      values.compact!
      values.min || 0.0
    rescue Elastomer::Reconciler::MaximumIdQueryFailedError
      0.0
    end

    # Estimate the time when the repair job will complete. If the job is already
    # finished, then the time the job finished is returend.
    #
    # Returns the estimated Time when the job will complete.
    def estimated_completion_time
      return stats[:finished] if finished?

      p = progress
      return nil unless p && p > 0

      started = stats[:started]
      return nil unless started

      estimated_duration = (Time.now - started).to_f * (100.0 / p)
      started + estimated_duration
    end

    # Retrieve stats for this repair job. The stats are returned as a single
    # Hash with the following keys
    #
    #   :started  - the Time when the job was first started
    #   :finished - the Time when the job completed or `false` if it is still running
    #   :elapsed  - time in seconds spent processing by the worker(s)
    #   :total    - the number of AR models that have been checked
    #   :added    - the number of documents added to the search index
    #   :updated  - the number of documents updated in the search index
    #   :removed  - the number of documents removed from the search index
    #   :error    - the number of errors encountered while repairing the search index
    #   :active   - the number of jobs currently active
    #
    # Returns the stats Hash.
    def stats
      keys = [STARTED_KEY, ELAPSED_KEY, ACTIVE_KEY]
      reconcilers.each { |r| keys.concat(r.keys) }

      ary = redis.hmget(group_key, *keys)

      hash = {
        total: 0,
        added: 0,
        updated: 0,
        removed: 0,
        error: 0,
        finished: [],
      }
      hash[:started] = ary.shift
      hash[:started] = Time.parse(hash[:started]) unless hash[:started].nil?
      hash[:elapsed] = ary.shift.to_f
      hash[:active]  = ary.shift.to_i

      ary.each_slice(6) do |total, added, updated, removed, error, finished|
        hash[:total]   += total.to_i
        hash[:added]   += added.to_i
        hash[:updated] += updated.to_i
        hash[:removed] += removed.to_i
        hash[:error]   += error.to_i
        hash[:finished] << (finished.nil? ? nil : Time.parse(finished))
      end

      hash[:finished] = hash[:finished].include?(nil) ? false : hash[:finished].max

      hash
    end

    # Clears out all job state from redis effectively stopping all workers and
    # losing all repair progress.
    #
    # Returns this repair job instance.
    def reset!
      GitHub.dogstats.increment("search.repair.reset", tags: datadog_tags)
      redis.del(group_key)
      self
    end

    def datadog_tags(**extra)
      tags = {
        index: "#{index_name}",
        search_cluster: "#{cluster_name}",
        repair_strategy: repair_strategy.serialize,
        search: "repair",
        job: self.class.name,
        target_scope: target_scope || "none",
      }

      tags.merge!({
        group_key:,
        repo_id:
      }) if emit_high_cardinality_tags?

      tags.merge!(extra)
      tags.map { |k, v| "#{k}:#{v}" }
    end

    # Returns `true` if the repair job group key exists in Redis. This
    # information lets us know if a repair job is already in place for the
    # search index.
    def exists?
      redis.exists?(group_key)
    end

    # Returns `true` if the repair job is enabled. When disabled, the
    # reconcilers will not perform any work. This is like pausing the repair
    # job.
    def enabled?
      1 == redis.hget(group_key, ENABLED_KEY).to_i
    end

    # Returns `true` if the repair job is disabled.
    def disabled?
      !enabled?
    end

    # Returns `true` if the repair job has been paused. The job exists but it
    # is not currently enabled.
    def paused?
      exists? && disabled?
    end

    # Returns `true` if the repair job is active. The job is enabled and not paused,
    # and it is not yet finished.
    def active?
      enabled? && !finished? && !paused?
    end

    # Enable the repair job.
    #
    # Returns this repair job instance.
    def enable
      redis.hset(group_key, ENABLED_KEY, 1)
      self
    end

    # Disable (or pause) the repair job.
    #
    # Returns this repair job instance.
    def disable
      redis.hset(group_key,
         ENABLED_KEY, 0,
         ACTIVE_KEY, 0,
         COMMITTED_KEY, 0,
         WORKER_KEY, 0
      )
      self
    end
    alias :pause :disable

    def job_args
      self.deserialize_arguments_if_needed if arguments.empty?
      arguments
    end

    def index_name
      return @index_name if defined?(@index_name)
      @index_name = job_args[0] # from ActiveJob base serialized args
    end

    def repo_id
      return @repo_id if defined?(@repo_id)
      @repo_id = job_opts[:repo_id]
    end

    sig { returns(T.nilable(Symbol)) }
    def target_scope
      return @target_scope if defined?(@target_scope)
      @target_scope = job_opts[:target_scope]
    end

    sig { returns(T.nilable(Integer)) }
    def target_scope_id
      return @target_scope_id if defined?(@target_scope_id)
      @target_scope_id = job_opts[:target_scope_id]
    end

    def job_opts
      return @job_opts if defined?(@job_opts)
      # from ActiveJob base serialized args, if present
      @job_opts = job_args.length > 1 ? job_args[1].with_indifferent_access : {}
    end

    def cluster_name
      return @cluster_name if defined?(@cluster_name)
      @cluster_name = job_opts[:cluster] || Elastomer.router.cluster_for_index(index_name)
    end

    def raise_errors?
      return @raise_errors if defined?(@raise_errors)
      @raise_errors = job_opts[:raise_errors] || raise_errors_override_enabled?
    end

    def raise_errors_override_enabled?
      return @raise_errors_override_enabled if defined?(@raise_errors_override_enabled)

      @raise_errors_override_enabled = FeatureFlag.vexi.enabled?(:elastomer_repair_raise_errors_override, index_name, default: false)
    end

    def upsert_only?
      @upsert_only ||= job_opts.fetch(:upsert_only, false)
    end

    # Force indexing is only allowed when there are no unapplied mapping changes.
    def force_reindex_allowed?
      index.update_mapping_supported? && !index.mapping_diff.changes?
    end

    sig { returns(T::Boolean) }
    def force_reindex?
      value = redis.hget(group_key, FORCE_REINDEX_KEY)
      return false if value.nil?
      value.to_i == 1
    end

    sig { params(value: T.nilable(T::Boolean)).void }
    def force_reindex=(value)
      cast_value = ActiveModel::Type::Boolean.new.cast(value)

      if enabled?
        raise ArgumentError, "Cannot change force_reindex on an enabled repair job. Reset the repair first."
      elsif cast_value && !force_reindex_allowed?
        raise ArgumentError, "Cannot enable force_reindex because there are unapplied mapping changes. Please apply the mapping changes and reset the repair job before setting force_reindex."
      end

      redis.hsetnx(group_key, FORCE_REINDEX_KEY, cast_value ? 1 : 0)
    end

    sig { override.returns(String) }
    def group_key
      return @group_key if defined?(@group_key)

      if target_scope.present? && target_scope_id.present?
        @group_key = "#{self.class.name}/#{index_name}/#{target_scope}:#{target_scope_id}"
      elsif repo_id.present?
        @group_key = "#{self.class.name}/#{index_name}/repo_id_#{repo_id}"
      else
        @group_key = "#{self.class.name}/#{index_name}"
      end
    end

    # The date where an index's corresponding MySQL records had to have been last updated before being repaired.
    # Any records that have updated_at < updated_at_start will be ignored.
    sig { returns(T.nilable(Time)) }
    def updated_at_start
      return unless (date = redis.hget(group_key, UPDATED_AT_START_KEY))

      Time.iso8601(date)
    end

    # Returns whether or not the partial repair strategy is used for this repair job.
    sig { returns(T::Boolean) }
    def updated_at_start?
      updated_at_start.present?
    end

    # Set the date where a MySQL record had to have been last updated before being repaired.
    sig { params(date: T.nilable(Time)).void }
    def updated_at_start=(date)
      if date
        if date.future?
          raise ArgumentError, "updated_at_start date cannot be in the future"
        end

        redis.hset(group_key, UPDATED_AT_START_KEY, date.iso8601)
      else
        redis.hdel(group_key, UPDATED_AT_START_KEY)
      end
    end

    # The maximum date where an index's corresponding MySQL records may have been last updated before being repaired.
    # Any records that have updated_at > upper_bound will be ignored.
    sig { returns(T.nilable(Time)) }
    def upper_bound
      return unless (date = redis.hget(group_key, UPPER_BOUND_KEY))

      Time.iso8601(date)
    end

    # Returns whether or not the partial repair strategy is used for this repair job.
    sig { returns(T::Boolean) }
    def upper_bound?
      upper_bound.present?
    end

    # Returns the strategy to use for the reconciliation process. By default, we repair all models otherwise we use
    # the PartialBackfill strategy if a time range is provided.
    sig { returns(Strategy) }
    def repair_strategy
      if updated_at_start? && upper_bound?
        Strategy::PartialBackfill
      else
        Strategy::AllModels
      end
    end

    # Set the upper bound on updated_at for MySQL records to be repaired.
    sig { params(date: T.nilable(Time)).void }
    def upper_bound=(date)
      if date
        if date.future?
          raise ArgumentError, "upper_bound date cannot be in the future"
        end
        redis.hset(group_key, UPPER_BOUND_KEY, date.iso8601)
      else
        redis.hdel(group_key, UPPER_BOUND_KEY)
      end
    end

    def reconcilers
      return @reconcilers if defined?(@reconcilers)

      @reconcilers = self.class.reconcilers.map do |hash|
        if repair_strategy == Strategy::PartialBackfill
          partial_opts = hash.merge(
            index: index,
            group_key: group_key,
            redis:,
            raise_errors: raise_errors?,
            start_date_time: updated_at_start,
            end_date_time: upper_bound,
            proc_args: [self]
          )
          partial_opts[:limit] = batch_size
          Elastomer::PartialBackfillReconciler.new(partial_opts)
        else
          # Use explicit delete_documents_from_es if set in reconcile config, otherwise fall back to !upsert_only?
          delete_documents = hash.key?(:delete_documents_from_es) ? hash[:delete_documents_from_es] : !upsert_only?

          resolved_force_reindex = hash.key?(:force_reindex) ? hash[:force_reindex] : force_reindex?
          reconciler_opts = hash.merge(
            index: index,
            group_key: group_key,
            redis: redis,
            raise_errors: raise_errors?,
            delete_documents_from_es: delete_documents,
            proc_args: [self],
            limit: batch_size,
          )
          reconciler_opts[:force_reindex] = resolved_force_reindex unless resolved_force_reindex.nil?

          Elastomer::Reconciler.new(reconciler_opts)
        end
      end
    end

    # Returns the Elastomer::Index instance that will be repaired. This index
    # is determined via the `index_name` and our Elastomer environment.
    def index
      return @index if defined? @index

      index_class = Elastomer.env.lookup_index(index_name)
      @index = index_class.new(index_name, cluster_name)
    end

    # Returns the number of workers that are actively processing this repair
    # job. This number does _not_ include workers that are queued.
    def working
      redis.hget(group_key, ACTIVE_KEY).to_i
    end

    # Returns the number of workers that the user has set for this repair
    def workers
      redis.hget(group_key, WORKER_KEY).to_i
    end

    # Returns the batch limit stored in Redis as an Integer.
    # their individually configured limits).
    sig { returns(Integer) }
    def batch_size
      return @batch_size if defined?(@batch_size)
      @batch_size = (redis.hget(group_key, BATCH_SIZE_KEY)&.to_i || default_batch_size)
    end

    sig { returns(Integer) }
    def default_batch_size
      self.class.reconcilers.map { |r| r[:limit] || Elastomer::Reconciler::DEFAULT_LIMIT }.first.to_i
    end

    # Set the batch limit for all reconcilers in this repair job.
    #
    # value - Integer number of AR models to fetch per batch. Pass 0 or a negative number to clear
    #         the override and revert to per-reconciler configured limits.
    #
    # Returns this repair job instance.
    sig { params(value: Integer).returns(T.self_type) }
    def batch_size=(value)
      @batch_size = value
      if value.zero? || value.negative?
        redis.hdel(group_key, BATCH_SIZE_KEY)
        @batch_size = default_batch_size
      else
        redis.hset(group_key, BATCH_SIZE_KEY, value)
      end
      self
    end

    # Internal: Put another job on the queue.
    #
    # Returns this job instance.
    def requeue
      self.class.perform_later(index_name, job_opts)
      self
    end

    # Internal: Return the redis connection to use for requests.
    def redis
      GitHub.legacy_redis
    end
    private :redis

    module ClassMethods
      # Add a document type to be reconciled in the search index.
      #
      # type - The document type to reconcile
      # opts - Options for the Reconciler
      #
      # Returns nil.
      def reconcile(type, opts = {})
        reconcilers << opts.merge(type: type)
        nil
      end

      # Create a new repair job and perform the work.
      #
      # name - The name of the index being repaired.
      # opts - Options Hash
      #        'cluster' - cluster name
      #
      # Returns the repair job instance.
      def perform(name, opts = {})
        Elastomer::RepairJob.new.perform(name, opts)
      end

      # Returns the queue where the repair job will run. You can override this
      # if needed, but most repair jobs should run from the :index_bulk queue.
      def queue
        :index_bulk
      end

      # Internal: the Array of reconciler configuration setttings.
      def reconcilers
        @reconcilers ||= []
      end
    end

    def self.inherited(job)
      job.extend ClassMethods
    end

    # No-op method to make testing easier.
    def self.reconcilers
      []
    end

    def validate_target_scope!
      return if target_scope.nil?
      raise InvalidRepairScopeError, "target_scope_id must be provided when target_scope is set" if target_scope_id.nil?
      reconcilers = self.class.reconcilers
      if reconcilers.empty?
        reconcilers = self.reconcilers
      end
      reconcilers.each do |r|
        # Handle both hash configs and Reconciler instances
        named_scopes = r.is_a?(Hash) ? r[:named_scopes] : r.named_scopes
        named_es_queries = r.is_a?(Hash) ? r[:named_elasticsearch_queries] : r.named_elasticsearch_queries
        type = r.is_a?(Hash) ? r[:type] : r.type

        unless named_scopes&.key?(target_scope)
          raise InvalidRepairScopeError, "target_scope #{target_scope} is not valid for reconciler #{type}"
        end
        unless upsert_only? || named_es_queries&.key?(target_scope)
          raise InvalidRepairScopeError, "target_scope #{target_scope} has no named_elasticsearch_query for reconciler #{type}; deletions would not be scoped correctly"
        end
      end
    end

    # Deprecation path: See issue https://github.com/github/elasticsearch/issues/9278
    def emit_high_cardinality_tags?
      return @emit_group_key_tag if defined?(@emit_group_key_tag)
      is_index_scoped = repo_id.nil? && target_scope.nil?

      @emit_group_key_tag = is_index_scoped || FeatureFlag.vexi.enabled?(
        :elastomer_repair_emit_high_cardinality_tags, group_key, default: false
      )
    end
  end
end
