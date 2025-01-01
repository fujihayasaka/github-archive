# typed: false
# frozen_string_literal: true

class ReminderPullRequestFilterBase
  # Repository IDs are used in IN statements.
  # There is no actual limit in SQL for the amount of values that IN can take
  # so we are using a conservative value here to be in the safe side.
  BATCH_SIZE = 100

  # NOTE: self.batch_* methods exists mainly for testing
  def self.batch_size
    @batch_size || BATCH_SIZE
  end

  def self.batch_size=(value)
    @batch_size = value
  end

  def self.reset_batch_size
    @batch_size = nil
  end

  def base_scope(repo_ids: nil)
    build_pull_requests_scope(build_repositories_scope(ids: repo_ids))
  end

  # If an organization has a high number of repositories, the query built to filter pull_requests
  # will have an `IN` statement with a big number of values. This can cause long running queries that
  # have to be killed.
  # By batching the repositories needed to filter pull_requests, we can hopefully avoid this problem
  def base_scope_in_batches(repo_ids: nil)
    build_repositories_scope_in_batches(ids: repo_ids) do |repositories|
      repositories.in_batches(of: self.class.batch_size) do |batch|
        if throttling_enabled?
          ApplicationRecord::Domain::IssuesPullRequests.throttle do
            yield build_pull_requests_scope(batch)
          end
        else
          yield build_pull_requests_scope(batch)
        end
      end
    end
  end

  protected

  def build_repositories_scope(ids: nil)
    ids = ids&.uniq
    repo_scope = Repository.active.not_archived_scope.owned_by_org(reminder.remindable)
    repo_scope = repo_scope.public_scope unless reminder.supports_private_repos?
    repo_scope = repo_scope.where(id: ids) if ids

    repo_scope.distinct
  end

  def build_repositories_scope_in_batches(ids: nil)
    ids = ids&.uniq
    repo_scope = build_repositories_scope

    return yield(repo_scope) unless ids

    # The list of ids can be too big, so we slice it and iterate
    # over each batch
    ids.each_slice(self.class.batch_size) do |batch|
      yield repo_scope.where(id: batch)
    end
  end

  def build_pull_requests_scope(repositories)
    scope = PullRequest
    if GitHub.flipper[:scheduled_reminders_process_job_skip_force_index].enabled?(reminder.user || reminder)
      # Here we want to check if we still need to use the FORCE INDEX, it looks like now it's causing timeouts
      # For more details, see: https://github.com/github/data-patterns-and-scaling/issues/117
      scope = scope.
        joins("INNER JOIN `issues` ON `issues`.`pull_request_id` = `pull_requests`.`id`")
    else
      # Using FORCE INDEX because MySQL optimizer will intermittently decide a `issues` table scan is the best plan.
      # For more details, see: https://github.com/github/database-infrastructure/issues/2381
      scope = scope.
        joins("INNER JOIN `issues` FORCE INDEX(`repository_id_and_state_and_pull_request_id_and_user`) ON `issues`.`pull_request_id` = `pull_requests`.`id`")
    end

    scope.where(issues: { state: "open" }).
      where(pull_requests: { user_hidden: false }).
      where(issues: { repository_id: repositories.pluck(:id) })
  end

  def throttling_enabled?
    GitHub.flipper[:scheduled_reminders_process_job_with_throttle].enabled?(reminder.user || reminder)
  end
end
