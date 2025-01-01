# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

require "database_selector"

module SmartDatabaseSelection
  extend ActiveSupport::Concern

  class MissingDatabaseDeclaration < RuntimeError; end

  MAX_REPLICATION_DELAY_WAIT_SECONDS = 2

  included do
    include ActiveJob::InitiallyEnqueuedAt

    retry_on WaitForReplication::DataUnavailable, attempts: :unlimited, wait: :polynomially_longer

    attr_accessor :started_waiting_at

    around_perform do |job, block|
      DatabaseSelector.instance.track_writes(DatabaseSelector::LastOperations.from_job(self)) do
        if job.class.default_to_write_connection?
          track_database_selection(:primary)
          with_write(&block)
        elsif job.class.primary_clusters
          track_database_selection(:mixed)

          # don't wait for replication on the clusters that will use a write connection
          primaries ||= self.class.primary_clusters
          flag_name = "lowercased_#{self.class.name.gsub(":", "_")}_primaries".underscore

          unless FeatureFlag.vexi.fully_disabled_or_raise?(flag_name) # rubocop: disable GitHub/FeatureManagement/NoVexiNonStandardUsage
            GitHub.schema_cached_models.select do |klass|
              actor = ClusterAsActor.new(klass.name)
              if FeatureFlag.vexi.enabled_or_raise?(flag_name, actor) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
                primaries |= [klass]
              end
            end
          end

          if tracked_replication_state.any?
            primaries.map(&:cluster_name).each do |cluster|
              @tracked_replication_state.delete(cluster)
            end
          end
          wait_for_replication(job.class.name, self.class.replica_clusters)
          with_declared_replicas do
            with_primaries(primaries) do
              block.call
            end
          end
        else
          track_database_selection(:replica)

          with_declared_replicas do
            if FeatureFlag.vexi.enabled_or_raise?(:active_job_replica_clusters_only) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
              wait_for_replication(job.class.name, self.class.replica_clusters)
            else
              wait_for_replication(job.class.name)
            end
            block.call
          end
        end
      end
    end
  end

  class_methods do
    attr_accessor :primary_clusters
    attr_accessor :replica_clusters
    attr_accessor :replica_clusters_with_lag

    # List of clusters that will get write connections. We won't wait for replication lag on these clusters.
    def use_primaries(*clusters)
      self.primary_clusters ||= []
      self.primary_clusters.concat(clusters)
    end

    # List of clusters that jobs expect to read from.
    # We will wait for replication lag to catch up on these clusters, if they also appear in tracked_replication_state.
    # If this list is defined, clusters not in this list will not be waited on.
    def use_replicas(*clusters, allow_replication_lag: [])
      self.replica_clusters ||= []
      self.replica_clusters.concat(clusters)
      self.replica_clusters_with_lag ||= []
      self.replica_clusters_with_lag.concat(allow_replication_lag)
    end

    def default_to_write_connection!
      @default_to_write_connection = true
    end

    def default_to_write_connection?
      @default_to_write_connection ||
      FeatureFlag.vexi.enabled_or_raise?(:active_job_default_to_write_connection, job_class_actor) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end
  end

  def serialize
    super.tap do |serialized_hash|
      serialized_hash["started_waiting_at"] = started_waiting_at.to_f if started_waiting_at
      serialized_hash["replication_state"] = tracked_replication_state if tracked_replication_state
    end
  end

  def deserialize(job_data)
    super

    if job_data["replication_state"]
      @tracked_replication_state = job_data["replication_state"].deep_symbolize_keys
    else
      @tracked_replication_state = nil
    end

    if job_data["started_waiting_at"]
      self.started_waiting_at = Time.at(job_data["started_waiting_at"])
    end
  end

  def wait_for_replication(job_name, replicas = nil)
    if tracked_replication_state.any? && replicas
      replicas ||= []
      # If replica_clusters are defined, only wait for those clusters (at most)
      # Add replicas to wait for via a FF if it exists, like `myjobclass_replicas`
      flag_name = "#{self.class.name.gsub(":", "_")}_replicas".underscore
      unless FeatureFlag.vexi.fully_disabled_or_raise?(flag_name) # rubocop: disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        GitHub.schema_cached_models.select do |klass|
          actor = ClusterAsActor.new(klass.name)
          if FeatureFlag.vexi.enabled_or_raise?(flag_name, actor) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            replicas |= [klass]
          end
        end
      end

      if replicas.any?
        # if replica list is populated, use it to filter out the other replicas
        replica_names = replicas.map(&:cluster_name)
        @tracked_replication_state.select! { |k, _| replica_names.include?(k) }
      end
    end

    self.started_waiting_at ||= Time.current
    waited_secs = WaitForReplication.new(
      tracked_replication_state,
      max_wait_seconds: MAX_REPLICATION_DELAY_WAIT_SECONDS,
      job_name: job_name,
    ).wait!

    # The replication_wait_ms metric is measured beginning from when the first attempt of the job was run.
    # We need to be careful to not emit it when the job gets rerun for non-wait reasons.
    #
    # For example imagine the following sequence of attempts to run a job:
    #   Attempt 1. The job would not catch up with the lag within the limit and wait! raises
    #              WaitForReplication::DataUnavailable
    #   Attempt 2. The job catches up with the lag. It starts executing perform which then raises some error.
    #   Attempt 3. The job does not have to wait at all since it had already caught up. It starts executing
    #              perform again and this time succeeds.
    # We want to emit the metric in attempt 2 but avoid doing it again in attempt 3.
    #
    # Our solution is to only emit if we had to wait during the current run or all recorded retry reasons are
    # waiting related.
    has_only_wait_retries = exception_executions.keys.all? { |k| k.include? WaitForReplication::DataUnavailable.name }
    if (waited_secs.present? && waited_secs > 0) || has_only_wait_retries
      GitHub.dogstats.distribution(
        "github.active_job.smart_database_selection.replication_wait_ms",
        (Time.current - started_waiting_at) * 1000,
        tags: all_stats_tags
      )
    end
  end

  def tracked_replication_state
    @tracked_replication_state ||= replication_state_to_persist
  end

  private

  def with_primaries(primaries = [], &block)
    if ActiveRecord::Base.single_database_cluster?
      return with_write(&block)
    end

    ActiveRecord::Base.connected_to_many(Array(primaries), role: :writing, &block)
  end

  def with_replicas(replicas = [], &block)
    if ActiveRecord::Base.single_database_cluster?
      return with_read(&block)
    end

    ActiveRecord::Base.connected_to_many(Array(replicas), role: :reading, &block)
  end

  def with_read(&block)
    ActiveRecord::Base.connected_to(role: :reading, &block)
  end

  def with_write(&block)
    ActiveRecord::Base.connected_to(role: :writing, &block)
  end

  def with_invalid(&block)
    ActiveRecord::Base.connected_to(role: :invalid, &block)
  rescue ActiveRecord::ConnectionNotDefined => e

    connection_model = e.connection_name
    connection_model = "ApplicationRecord::Mysql1" if connection_model == "ActiveRecord::Base"
    raise MissingDatabaseDeclaration, "You attempted to access a database connection for #{connection_model} which is not declared in #{self.class}.", e.backtrace
  end

  def with_declared_replicas
    if self.class.replica_clusters && (!Rails.env.production? || FeatureFlag.vexi.enabled_or_raise?(:with_declared_replicas)) # rubocop:disable GitHub/DoNotBranchOnRailsEnv, GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      with_invalid do
        with_replicas(self.class.replica_clusters + self.class.replica_clusters_with_lag) do
          yield
        end
      end
    else
      with_read do
        yield
      end
    end
  end

  def track_database_selection(type)
    GitHub.dogstats.increment("github.active_job.smart_database_selection.database_selected", tags: all_stats_tags.concat(["type:#{type}"]))
  end

  def replication_state_to_persist
    DatabaseSelector::ReplicationState.current&.to_hash
  end
end
