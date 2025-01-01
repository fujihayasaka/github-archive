# typed: strict
# frozen_string_literal: true

# This job deletes the dependency graph data for an orphaned repository.
module DependencyGraph
  class DeleteOrphanRepositoryJob < ApplicationJob
    include DependencyGraph::RetryJob
    include GitHub::Memoizer

    queue_as :dependency_graph_disable_repo

    retry_on_dirty_exit

    use_primaries ApplicationRecord::Repositories

    # This feature flag is used to determine if an orphaned repo may be deleted
    ALLOW_DELETION_ORPHANED_REPO_FLAG = "dependency_graph_allow_deletion_of_orphaned_repos"

    # If the source is not provided, it will be set to "unknown" by default.
    DEFAULT_SOURCE = "unknown"

    # This is the default message that will be logged when the job is skipped.
    SKIP_MESSAGE = "Deleting orphaned repo skipped"

    # Prefix for metrics related to this job.
    METRICS_PREFIX = "dependency_graph.jobs.delete_orphan_repo"

    # This job is used to delete the dependency graph data for an orphaned repository.
    #
    # An orphaned repository in this context is defined as:
    # - a repository with DG data but a non-existent repository id
    # - a repository with DG data but DG is disabled
    #
    # Example usage:
    #   DeleteOrphanRepositoryJob.perform_later(repository_id: 123, source: "scheduled-job")
    #
    sig { params(repository_id: Integer, source: String).void }
    def perform(repository_id: 0, source: DEFAULT_SOURCE)
      if repository_id == 0
        report_skip("invalid_repo_id")
        return
      end

      unless orphan_deletion_allowed?
        report_skip("feature_disabled")
        return
      end

      reason = "non_existent_repo"

      repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
        T.cast(Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      else
        Repository.find_by(id: repository_id)
      end
      if repository
        reason = "dg_disabled"
        dependency_graph_service = SecurityProduct::DependencyGraph.new(repository)
        result, error = dependency_graph_service.can_delete_orphaned?
        unless !!result
          report_skip("#{error.to_s.gsub(' ', '_').downcase}")
          return
        end
      end

      DependencyGraphPlatform.publish_orphaned_manifest_reset_event(
        repository_id: repository_id,
        actor: User.staff_user,
        action: :RESET_ACTION_CLEAR,
        trigger: :RESET_TRIGGER_MASS_OFFBOARD
      )

      GitHub.dogstats.increment(
        "#{METRICS_PREFIX}.enqueued",
        tags: all_stats_tags + ["reason:#{reason}"]
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

    # Only allow disabling of inactive repositories if the feature flag is enabled
    # Checking feature for staff_user since orphaned repos may not exist in the DB
    sig { returns(T::Boolean) }
    def orphan_deletion_allowed?
      return false if GitHub.enterprise?

      ::DependencyGraph.check_feature_for_user(User.staff_user, ALLOW_DELETION_ORPHANED_REPO_FLAG)
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

    sig { params(cause: String).void }
    def report_skip(cause)
      GitHub.logger.warn(SKIP_MESSAGE, logging_context.merge("cause" => cause))
      GitHub.dogstats.increment(
        "#{METRICS_PREFIX}.skipped",
        tags: all_stats_tags + ["cause:#{cause}"]
      )
    end
  end
end
