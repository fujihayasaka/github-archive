# typed: false
# frozen_string_literal: true

class ReminderPullRequestFilterBase
  # Repository IDs are used in IN statements.
  # There is no actual limit in SQL for the amount of values that IN can take
  # so we are using a conservative value here to be in the safe side.
  BATCH_SIZE = 100
  # Define limits for the number of pull requests to be returned
  # For each reminder, we will return up to 5 repositories with the oldest average PR age
  # and up to 20 oldest PRs per repository.
  REPO_LIMIT = 5
  PULL_REQUEST_LIMIT = 20

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

  # This function separates a Scientist experiment that runs on personal reminders only. This is because
  # we have identified problems with issues indexing leading to slow queries in that area and separating helps
  # to evaluate the impact.
  def base_scope_in_batches_personal_reminders(repo_ids: nil)
    build_repositories_scope_in_batches(ids: repo_ids) do |repositories|
      repositories.in_batches(of: self.class.batch_size) do |batch|
        if throttling_enabled?
          ApplicationRecord::Domain::IssuesPullRequests.throttle do
            yield build_pull_requests_scope_experiment(batch)
          end
        else
          yield build_pull_requests_scope_experiment(batch)
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
    if FeatureFlag.vexi.enabled?(:scheduled_reminders_process_job_skip_force_index, reminder.user || reminder, default: false)
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

  def build_pull_requests_scope_experiment(repositories)
    Scientist.run("personal_reminder_pull_request_filter_ignore_index") do |experiment|
      experiment.use do
        build_pull_requests_scope(repositories)
      end
      experiment.try do
        PullRequest.
        joins("INNER JOIN `issues` IGNORE INDEX(`issues_on_pull_request_id_unique`) ON `issues`.`pull_request_id` = `pull_requests`.`id` ").
        where(issues: { state: "open" }).
        where(pull_requests: { user_hidden: false }).
        where(issues: { repository_id: repositories.pluck(:id) })
      end
      experiment.compare { true }
    end
  end

  def throttling_enabled?
    FeatureFlag.vexi.enabled?(:scheduled_reminders_process_job_with_throttle, reminder.user || reminder, default: false)
  end

  def apply_limits(pull_requests)
    # Select up to 5 repositories with the oldest average PR age
    repo_ids_with_oldest_avg_age = PullRequest
     .select("pull_requests.repository_id, AVG(pull_requests.created_at)")
     .group("pull_requests.repository_id")
     .order("AVG(pull_requests.created_at) ASC")
     .where(id: pull_requests.map(&:id))
     .limit(REPO_LIMIT)
     .pluck(:repository_id)

    # Fetch up to 20 oldest PRs per repository
    pull_requests_filtered = PullRequest
    .where(repository_id: repo_ids_with_oldest_avg_age)
    .where(id: pull_requests.map(&:id))
    .order(:repository_id, :created_at)
    .to_a
    .group_by(&:repository_id)

    # Limit to 20 pull requests per repository
    limited_pull_requests = pull_requests_filtered.flat_map do |_, prs|
      prs.first(PULL_REQUEST_LIMIT) # Take the first 20 pull requests per repository
    end
    limited_pull_requests
  end

  def updated_limits_enabled?
    return @updated_limits_enabled if defined?(@updated_limits_enabled)
    @updated_limits_enabled = FeatureFlag.vexi.enabled?("scheduled_reminders_updated_limits", reminder.user, default: false)
  end
end
