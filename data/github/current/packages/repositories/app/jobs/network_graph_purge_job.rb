# typed: true
# frozen_string_literal: true

# This job purges stale Repository::NetworkGraph records that were never built.
# Records are eligible for purge if built_at is nil and updated_at is older than 1 week.
class NetworkGraphPurgeJob < ApplicationJob
  queue_as :network_graph_purge
  retry_on_dirty_exit

  INTERVAL = 2.minutes
  LOCK_TIMEOUT = 10.minutes
  # Only one of these jobs should run at any given time.
  locked_by timeout: LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  schedule interval: INTERVAL

  exempt_from_tenant_context_requirement

  JOB_SIZE = 5_000
  STALE_THRESHOLD = 30.days
  ACCEPTABLE_DELAY_SECONDS = 1.0
  CLUSTER_NAME = :collab

  def high_replication_lag?
    delay = Freno.client.replication_delay(store_name: CLUSTER_NAME)
    delay > ACCEPTABLE_DELAY_SECONDS
  rescue Freno::Error
    true
  end

  def perform
    return 0 unless FeatureFlag.vexi.enabled?(:network_graph_purge, default: false)

    if high_replication_lag?
      GitHub.dogstats.increment("network_graph_purge.skipped_high_lag")
      GitHub.logger.info(
        "Skipping network graph purge due to high replication lag",
        "code.namespace" => self.class.name,
        "code.function" => __method__
      )
      return 0
    end

    batch_ff = FeatureFlag.vexi.percentage_of_calls_value_or_raise(:network_graph_purge_batch_size) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
    job_ff = FeatureFlag.vexi.percentage_of_calls_value_or_raise(:network_graph_purge_job_size) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage

    batch_size = batch_ff > 0 ? batch_ff.to_i : 100 # 0 - 100
    job_size = job_ff > 0 ? job_ff.to_i * 100 : JOB_SIZE # 0 - 10_000

    cutoff_time = STALE_THRESHOLD.ago

    # delete() only works because there are no destroy callbacks on Repository::NetworkGraph
    # so it's OK to just delete the row directly
    purged_count = 0
    ids = Repository::NetworkGraph.where(built_at: nil).where("updated_at < ?", cutoff_time).limit(job_size).pluck(:id)
    ids.each_slice(batch_size) do |batch_ids|
      Repository::NetworkGraph.throttle_with_retry(max_retry_count: 3) do
        with_write { purged_count += Repository::NetworkGraph.delete(batch_ids) }
      end
    end

    ids = Repository::NetworkGraph.where("built_at < ?", cutoff_time).limit(job_size).pluck(:id)
    ids.each_slice(batch_size) do |batch_ids|
      Repository::NetworkGraph.throttle_with_retry(max_retry_count: 3) do
        with_write { purged_count += Repository::NetworkGraph.delete(batch_ids) }
      end
    end

    GitHub.dogstats.gauge("network_graph_purge.purged", purged_count)

    GitHub.logger.info(
      "Performing network graph purge job",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "network_graph.purge.cutoff_time" => cutoff_time,
      "network_graph.purge.count" => purged_count,
      "network_graph.purge.batch_size" => batch_size
    )

    purged_count
  end
end
