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
    queue_as :index_bulk

    include GitHub::ServiceMapping

    ENABLED_KEY = "enabled".freeze
    ELAPSED_KEY = "elapsed".freeze
    STARTED_KEY = "started".freeze
    ACTIVE_KEY  = "active".freeze
    WORKER_KEY  = "workers".freeze
    UPDATED_AT_START_KEY = "updated_after_start".freeze
    UPPER_BOUND_KEY = "upper_bound".freeze
    FINISHED_KEY = "finished_at".freeze

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
      # Set the customer-requested worker value in Redis
      redis.hset(group_key, WORKER_KEY, count)
      active_jobs = redis.hget(group_key, ACTIVE_KEY).to_i

      # Only start more jobs if active_job count is less than count
      count = [0, count - active_jobs].max

      count.times { requeue }
      redis.hsetnx(group_key, STARTED_KEY, Time.now.iso8601)
      GitHub.dogstats.gauge("search.repair.workers", count, { tags: [
        "index:#{index_name}",
        "group_key:#{group_key}",
        "search_cluster:#{cluster_name}"
      ] })
      GitHub.dogstats.gauge("search.repair.active_jobs", active_jobs, { tags:
        ["index:#{index_name}", "group_key:#{group_key}", "search_cluster:#{cluster_name}"]
      })
      GitHub.dogstats.event(
        "Repair Job Started",
        "Started repair job for index #{index_name} with #{count} workers", tags: [
          "index:#{index_name}",
          "search_cluster:#{cluster_name}",
          "group_key:#{group_key}",
        ]
      )
    end

    # Perform the actual work of reconciling the search index with the canoncial
    # data source. This method will check the `enabled` flag and only perform
    # work if the flag is true. This method will enqueue another repair job
    # if there are more iterations to perform.
    #
    # Returns this repair job instance.
    def perform(name, opts = {})
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
      GitHub.dogstats.increment("search.repair.batch_start", { tags: [
        "index:#{index_name}",
        "group_key:#{group_key}",
        "search_cluster:#{cluster_name}",
      ] })

      GitHub.logger.info(
        "Starting repair job for index #{name} with options: #{opts.inspect}",
        tags: logger_tags
      )
      repair!

    ensure
      active_jobs = redis.hget(group_key, ACTIVE_KEY).to_i
      worker_count = redis.hget(group_key, WORKER_KEY).to_i
      should_requeue = enabled? && !finished? && (worker_count > active_jobs)
      GitHub.dogstats.increment("search.repair.batch_complete", { tags: [
        "index:#{index_name}",
        "requeue:#{should_requeue}",
        "enabled:#{enabled?}",
        "finished:#{finished?}",
        "has_worker_capacity:#{worker_count > active_jobs}",
        "group_key:#{group_key}",
        "search_cluster:#{cluster_name}",
      ] })
      GitHub.dogstats.gauge("search.repair.progress", progress, {
        tags: [
          "index:#{index_name}",
          "group_key:#{group_key}",
          "search_cluster:#{cluster_name}",
        ]
      })
      requeue if should_requeue
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
      redis.hincrby(group_key, ACTIVE_KEY, 1)

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

      GitHub.dogstats.timing("search.repair.elapsed", (elapsed * 1000).round, { tags: ["index:#{index_name}"] })

      self
    rescue StandardError => boom # rubocop:todo Lint/GenericRescue
      Failbot.report(boom.with_redacting!)
      raise if raise_errors?
    ensure
      active_jobs = redis.hget(group_key, ACTIVE_KEY).to_i
      redis.hincrby(group_key, ACTIVE_KEY, -1) if active_jobs > 0
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
        GitHub.logger.info(
          "Repair job for index #{index_name} with group key #{group_key} marked complete at #{completed_at}",
          tags: logger_tags
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
      values.min
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
      GitHub.logger.warn(
        "Resetting repair job for index #{index_name} with group key #{group_key}",
        tags: logger_tags
      )
      redis.del(group_key)
      self
    end

    def logger_tags
      [
        "index:#{index_name}",
        "group_key:#{group_key}",
        "search_cluster:#{cluster_name}",
        "repo_id:#{repo_id}",
        "enabled:#{enabled?}",
        "active:#{active?}",
        "finished:#{finished?}",
        "raise_errors:#{raise_errors?}",
        "repair_strategy:#{repair_strategy}",
      ]
    end

    # Returns `true` if the repair job group key exists in Redis. This
    # information lets us know if a repair job is already in place for the
    # search index.
    def exists?
      redis.exists(group_key)
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

    # Returns `true` if the repair job is active. The job is enabled but it is
    # not yet finished.
    def active?
      enabled? && !finished?
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
      redis.hset(group_key, ENABLED_KEY, 0)
      redis.hset(group_key, ACTIVE_KEY, 0)
      redis.hset(group_key, WORKER_KEY, 0)
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
      @raise_errors = job_opts[:raise_errors]
    end

    def group_key
      return @group_key if defined?(@group_key)
      @group_key = "#{self.class.name}/#{index_name}"
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
          Elastomer::PartialBackfillReconciler.new(hash.merge(
            index: index,
            group_key: group_key,
            redis:,
            raise_errors: raise_errors?,
            start_date_time: updated_at_start,
            end_date_time: upper_bound,
            proc_args: [self]
          ))
        else
          Elastomer::Reconciler.new(hash.merge(
            index: index,
            group_key: group_key,
            redis: redis,
            raise_errors: raise_errors?,
            proc_args: [self]
          ))
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

    # Internal: Put another job on the queue.
    #
    # Returns this job instance.
    def requeue
      self.class.perform_later(*job_args)
      self
    end

    # Internal: Return the redis connection to use for requests.
    def redis
      GitHub.job_coordination_redis
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
  end
end
