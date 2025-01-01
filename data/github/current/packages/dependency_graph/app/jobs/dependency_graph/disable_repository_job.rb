# typed: strict
# frozen_string_literal: true

# This job disables the dependency graph for a repository.
module DependencyGraph
  class DisableRepositoryJob < ApplicationJob
    include DependencyGraph::RetryJob
    include GitHub::Memoizer

    queue_as :dependency_graph_disable_repo

    retry_on_dirty_exit

    # Ensures we have the current state of enablement and allows us to write/delete changes
    use_primaries ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,             # Cluster where legacy dependency graph configurations are stored
      ApplicationRecord::SecurityProductsEnablement, # Cluster where new dependency graph configurations are stored
      ApplicationRecord::Notify                      # Cluster where enterprise policy configurations are stored

    # This feature flag is used to determine if inactive repositories may be disabled,
    ALLOW_DISABLE_INACTIVE_REPO_FLAG = "dependency_graph_allow_disable_of_inactive_repos"

    # If the source is not provided, it will be set to "unknown" by default.
    DEFAULT_SOURCE = "unknown"

    # This is the default message that will be logged when the job is skipped.
    SKIP_MESSAGE = "Disabling dependency graph skipped"

    # Prefix for metrics related to this job.
    METRICS_PREFIX = "dependency_graph.jobs.disable_repository"

    # This job is used to disable the dependency graph for a repository.
    #
    # Example usage:
    #   DisableRepositoryJob.perform_later(repository_id: 123, source: "scheduled-job")
    #
    sig { params(repository_id: Integer, source: String).void }
    def perform(repository_id: 0, source: DEFAULT_SOURCE)
      if repository_id == 0
        report_skip("invalid_repo_id")
        return
      end

      repository = Repository.find_by(id: repository_id)
      unless repository
        report_skip("repo_not_found")
        return
      end

      # Used for logging and metrics purposes.
      visibility = repository.visibility

      unless disablement_allowed?(repository)
        report_skip("feature_disabled", visibility: visibility)
        return
      end

      dependency_graph_service = SecurityProduct::DependencyGraph.new(repository)

      unless dependency_graph_service.enabled?
        report_skip("already_disabled", visibility: visibility)
        return
      end

      result, error = dependency_graph_service.disable(actor: User.ghost)
      unless !!result
        report_skip("#{error.to_s.gsub(' ', '_').downcase}", visibility: visibility)
        return
      end

      GitHub.dogstats.increment(
        "#{METRICS_PREFIX}.disabled",
        tags: all_stats_tags + ["visibility:#{visibility}"]
      )
    end

    protected

    sig { override.returns(T::Array[String]) }
    def stats_tags
      [
        "metric_type:dependency_graph",
        "source:#{source}",
      ].compact
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "job.source" => source,
        "job.queue" => queue_name,
        "job.repo_id" => repository_id
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "dependency_graph"
      })
    end

    private

    # Only allow disabling of inactive repositories if the feature flag is enabled and if not enterprise
    sig { params(repository: Repository).returns(T::Boolean) }
    def disablement_allowed?(repository)
      ::DependencyGraph.check_feature_for_repo_or_owner(repository, ALLOW_DISABLE_INACTIVE_REPO_FLAG)
    end

    # This method is used to determine the source of the job.
    # It is used for logging and metrics purposes.
    sig { returns(String) }
    memoize def source
      (arguments[0] || {}).fetch(:source, DEFAULT_SOURCE)
    end

    # This method is used to determine the repository_id of the job.
    # It is used for logging and metrics purposes.
    sig { returns(Integer) }
    memoize def repository_id
      (arguments[0] || {}).fetch(:repository_id, 0)
    end

    sig { params(cause: String, visibility: String).void }
    def report_skip(cause, visibility: "unknown")
      GitHub.logger.warn(SKIP_MESSAGE, logging_context.merge("cause" => cause, "visibility" => visibility))
      GitHub.dogstats.increment(
        "#{METRICS_PREFIX}.skipped",
        tags: all_stats_tags + ["cause:#{cause}", "visibility:#{visibility}"]
      )
    end
  end
end
