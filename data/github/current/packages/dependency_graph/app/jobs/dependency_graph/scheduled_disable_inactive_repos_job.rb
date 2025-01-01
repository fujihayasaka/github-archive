# typed: strict
# frozen_string_literal: true

# This job runs on a schedule to disable the dependency graph for inactive repositories.
module DependencyGraph
  class ScheduledDisableInactiveReposJob < ApplicationJob
    include RetryJob

    schedule interval: 4.weeks

    # Using the same queue as the FindInactiveReposJob
    queue_as :dependency_graph_find_inactive_repos

    retry_on_dirty_exit

    # This feature flag is used to determine if the scheduled job should run.
    ALLOW_DISABLE_INACTIVE_REPO_FLAG = "dependency_graph_allow_scheduled_disablement_of_inactive_repos"

    # Prefix for metrics related to this job.
    METRICS_PREFIX = "dependency_graph.jobs.scheduled_disable_inactive_repos"

    # Scheduled job defaults (will override FindInactiveReposJob defaults, if different)
    DEFAULT_BATCH_SIZE = 1000
    DEFAULT_LIMIT = 1_000_000
    DEFAULT_MAX_STARS = 1
    DEFAULT_MAX_YEARS = 3
    DEFAULT_SKIP_ENTERPRISE = true
    DEFAULT_SOURCE = "scheduled-job"
    DEFAULT_DRY_RUN = true # TODO: switch to false when ready

    sig { void }
    def perform
      unless disablement_allowed?
        GitHub.logger.info(
          "#{self.class.name} is disabled by feature flag: #{ALLOW_DISABLE_INACTIVE_REPO_FLAG}",
          logging_context
        )
        GitHub.dogstats.increment("#{METRICS_PREFIX}", tags: all_stats_tags + ["status:skipped", "reason:flag_disabled"])
        return
      end

      # Enqueuing the FindInactiveReposJob with the default parameters for the scheduled job.
      FindInactiveReposJob.perform_later(
        batch_size: DEFAULT_BATCH_SIZE,
        limit: DEFAULT_LIMIT,
        max_stars: DEFAULT_MAX_STARS,
        max_years: DEFAULT_MAX_YEARS,
        skip_enterprise: DEFAULT_SKIP_ENTERPRISE,
        source: DEFAULT_SOURCE,
        dry_run: DEFAULT_DRY_RUN,
      )

      GitHub.dogstats.increment("#{METRICS_PREFIX}", tags: all_stats_tags + ["status:enqueued"])
      GitHub.logger.info("#{self.class.name} enqueued FindInactiveReposJob", logging_context)
    end

    protected

    sig { override.returns(T::Array[String]) }
    def stats_tags
      ["metric_type:dependency_graph"].compact
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "job.limit" => DEFAULT_LIMIT,
        "job.batch_size" => DEFAULT_BATCH_SIZE,
        "job.max_stars" => DEFAULT_MAX_STARS,
        "job.max_years" => DEFAULT_MAX_YEARS,
        "job.skip_enterprise" => DEFAULT_SKIP_ENTERPRISE,
        "job.source" => DEFAULT_SOURCE,
        "job.dry_run" => DEFAULT_DRY_RUN,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "dependency_graph"
      })
    end

    private

    # Only run the job if the feature flag is enabled.
    sig { returns(T::Boolean) }
    def disablement_allowed?
      ::DependencyGraph.check_feature_for_user(User.ghost, ALLOW_DISABLE_INACTIVE_REPO_FLAG)
    end
  end
end
