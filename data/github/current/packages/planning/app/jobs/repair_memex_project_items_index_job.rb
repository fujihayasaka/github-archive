# typed: true
# frozen_string_literal: true

# RepairMemexProjectItemsIndexJob is a job that coordinates and reconciles the MemexProjectItems index. The job is
# intended to be run to populate an entire memex-project-items index or to repair it in case of data consistency
# issues.
#
# The repair job uses a custom reconcilation strategy for performance reasons to iterate over MemexProject records
# instead of the default MemexProjectItem records. This guarantees we reconcile a single project at a time and can
# efficiently preload and cache column data necessary for the reconciliation process.
#
# The job is designed to be idempotent and can be safely retried in case of failure. The job will retry all exceptions
# at least 3 times before failing permanently. If there are any batches that are not able to be reconciled, the job
# will store the batch in Redis to indicate that it needs to be retried manually.
#
# This job offers two repair strategies to determine which MemexProjects are repaired. The #strategy method returns
# which strategy is being used for a given repair. Only be one repair strategy will be used, changing the strategy
# will start from the beginning.
#
# 1. All projects (default)
#    All MemexProjects will be repaired.
#
# 2. Visited after
#    Only repairs MemexProjects that have been visited since the specified date.
#
# To repair a single project look to use the ResyncMemexProjectItemsIndexJob directly as we do for automated failures
# within Projects::DenormalizationProcessor.
class RepairMemexProjectItemsIndexJob < Elastomer::RepairJob
  include GitHub::Memoizer

  VISITED_AFTER_KEY = "visited-after".freeze

  class Strategy < T::Enum
    enums do
      # AllProjects is a strategy that reconciles all MemexProjects.
      AllProjects = new("all_projects")

      # VisitedAfter is a strategy that reconciles MemexProjects that have been visited after a given date.
      VisitedAfter = new("visited_after")
    end
  end

  queue_as :index_bulk

  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  # Retry the repair process on any StandardError exception that is raised during the reconciliation process.
  # The reconciliation process will restart from the last successfully reconciled project.
  retry_on StandardError, attempts: 3, wait: :polynomially_longer do |job, error|
    job.reconciler.failed!(error)
  end

  # The date where a MemexProject has to have been last visited since. Used to filter projects and prepare
  # batches to reconcile. If no date is provided, all MemexProjects will be reconciled.
  sig { returns(T.nilable(Date)) }
  def visited_after
    return unless (date = redis.hget(group_key, VISITED_AFTER_KEY))

    Date.iso8601(date)
  end

  # Returns whether or not the VisitedAfter strategy is used for this repair job.
  sig { returns(T::Boolean) }
  def visited_after?
    visited_after.present?
  end

  # Set the date where a MemexProject has to have been last visited since before being repaired.
  sig { params(date: T.nilable(Date)).void }
  def visited_after=(date)
    if date
      if date.future?
        raise ArgumentError, "visited_after date cannot be in the future"
      end

      redis.hset(group_key, VISITED_AFTER_KEY, date.iso8601)
    else
      redis.hdel(group_key, VISITED_AFTER_KEY)
    end
  end

  def to_partial_path
    "stafftools/search_indexes/repair_jobs/memex_project_items/repair_job"
  end

  # Reset the reconciler by clearing all redis keys.
  #
  # Returns this reconciler.
  def reset!
    # Need to reset the child reconcilers before the entire repair job for proper cleanup.
    reconcilers.each(&:reset!)
    super
  end

  # Default to raising errors to allow for bubbling up exceptions necessary for retries.
  sig { returns(T::Boolean) }
  def raise_errors?
    true
  end

  sig { returns(MemexProjectItems::Reconciler) }
  def reconciler
    T.must(reconcilers.first)
  end

  # Returns the strategy to use for the reconciliation process. By default, we repair all projects otherwise we use
  # the VisitedAfter strategy if a date is provided.
  sig { returns(Strategy) }
  def strategy
    if visited_after?
      Strategy::VisitedAfter
    else
      Strategy::AllProjects
    end
  end

  sig { returns(T::Array[MemexProjectItems::Reconciler]) }
  memoize def reconcilers
    reconcilers = []
    if strategy == Strategy::VisitedAfter
      reconcilers << MemexProject::VisitedAfterReconciler.new(
        index:,
        group_key:,
        redis:,
        raise_errors: raise_errors?,
        reconcile_id: job_id,
        attempt: executions,
        visited_after:,
      )
    else
      reconcilers << MemexProjectItems::Reconciler.new(
        index:,
        group_key:,
        redis:,
        raise_errors: raise_errors?,
        reconcile_id: job_id,
        attempt: executions,
      )
    end
    reconcilers
  end
end
