# frozen_string_literal: true
require_relative "../../lib/dependency_graph/connection"

# This job deletes the given repository entry (given by github_repository_id)
# in order to clear the dependencies for that repository.
# It should be enqueued to Aqueduct in ResetManifestsProcessor and is pulled off the queue
# by the aqueduct-worker.
class ClearDependenciesJob < RetryJob
  include DependencyGraph::Connection
  queue_as :dg_disabling

  BATCH_SIZE = 200

  def self.queue_options
    { redelivery_timeout_secs: 10 * 60 } # 10 minutes in seconds
  end

  def is_backfill?
    false
  end

  # Used by general metrics defined in config/initializers/instrumentation.rb
  def stats_tags
    ["backfill:#{is_backfill?}"]
  end

  # Returns the name of the job for logging and instrumentation
  # This can be overridden by subclasses to use different job names
  def job_name
    "clear_dependencies_job"
  end

  # Returns the metric name to use for instrumentation
  # This can be overridden by subclasses to use different metrics
  def metric_name
    "etl.#{job_name}"
  end

  def tags_for_logging(github_repository_id)
    {
      "job.name" => "#{job_name}",
      "gh.repo.id" => github_repository_id,
      "backfill" => is_backfill?
    }
  end

  def perform(github_repository_id, log_context: {})
    repository = Repository.find_by_github_repository_id(github_repository_id)

    unless repository.present?
      DependencyGraph.logger.info(
        "Could not find Repository by github_repository_id",
        tags_for_logging(github_repository_id).merge(log_context))
      Instrument.increment(metric_name, result: "repo_not_found", backfill: is_backfill?)
      return
    end

    DependencyGraph.logger.with_named_tags(
      tags_for_logging(repository.github_repository_id)
        .merge({ "gh.repo.public": repository.public? })
        .merge(log_context)) do

      begin
        DependencyGraph.throttler.throttle(:"dependency-graph") do
          repository.manifests.in_batches(of: BATCH_SIZE) do |batch_of_manifests|
            batch_of_manifests.each do |manifest|
              DependencyGraph.logger.info("Destroying manifest", "gh.manifest.id" => manifest.id)
              # Use a separate transaction with READ COMMITTED isolation level for each manifest
              with_read_committed(role: :writing) do
                manifest.destroy
              end
            end
          end
        end

        DependencyGraph.logger.info("Deleting all abstract dependencies")
        DependencyGraph.throttler.throttle(:"dependency-graph") do
          repository.abstract_dependencies.select(:id).in_batches(of: BATCH_SIZE) do |batch_of_deps|
            # Using `delete_all` here instead of `destroy_all` for efficiency sake
            # since abstract dependencies don't have any callbacks or associations to be destroyed
            batch_of_deps.delete_all
          end
        end

        DependencyGraph.logger.info("Destroying all star counts")
        StarCount
          .select(:id)
          .where(github_repository_id: repository.github_repository_id)
          .destroy_all # should only be one of these per repo!

      rescue StandardError => e
        DependencyGraph.logger.error("Execution error", "exception.type" => e.class.name)
        Instrument.increment(metric_name, result: "failed", error: e.class.name, backfill: is_backfill?)

        raise e
      end

      DependencyGraph.logger.info("Execution success")
      Instrument.increment(metric_name, result: "successful", backfill: is_backfill?)
    end
  end
end
