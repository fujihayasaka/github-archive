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

  def base_scope_in_batches(repo_ids: nil)
    build_repositories_scope_in_batches(ids: repo_ids) do |repositories|
      repositories.in_batches(of: self.class.batch_size) do |batch|
        ApplicationRecord::Domain::IssuesPullRequests.throttle do
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
    # There's a covering index `index_pull_requests_on_repository_id_user_hidden_and_status`
    PullRequest.
      where(status: "open").
      where(user_hidden: false).
      where(repository_id: repositories.pluck(:id))
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
end
