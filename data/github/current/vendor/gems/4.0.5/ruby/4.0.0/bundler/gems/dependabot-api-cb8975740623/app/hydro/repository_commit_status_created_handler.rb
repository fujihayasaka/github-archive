# frozen_string_literal: true

class RepositoryCommitStatusCreatedHandler
  attr_reader :commit_sha, :state, :repository_id

  def self.run(message)
    commit_sha = message.value.fetch(:commit_sha)
    state = message.value.fetch(:state)
    repository_id = message.value.fetch(:repository_id)

    new(commit_sha, state, repository_id).run
  end

  def initialize(commit_sha, state, repository_id)
    @commit_sha = commit_sha
    @state = state
    @repository_id = repository_id
  end

  def run
    ActiveRecord::Base.connected_to(role: :reading) do
      # If the event has not completed, it will be followed up by another
      # event later when the status changes to a terminal value.  Dependabot currently
      # only performs lookups and comparisons on PRs with terminal CI statuses,
      # so we can skip processing these events.
      return unless completed? && active_account?

      update_pr_ci_statuses
    end
  end

  private

  def completed?
    %i(SUCCESS FAILURE ERROR).include?(state)
  end

  def active_account?
    repository&.account&.active?
  end

  def update_pr_ci_statuses
    affected_dependabot_prs.each do |pr|
      UpdatePullRequestCiStatusJob.set(scheduling_properties).perform_later(
        pull_request: pr,
        refs_to_check: [commit_sha],
      )
    end
  end

  def scheduling_properties
    {
      wait: UpdatePullRequestCiStatusJob::DEBOUNCE_PERIOD,
    }
  end

  def affected_dependabot_prs
    @affected_dependabot_prs ||= [
      *pull_requests_with_matching_head_commit,
      *pull_requests_with_matching_base_commit,
      *pull_requests_with_matching_dependabot_commit,
    ].uniq
  end

  def pull_requests_for_repo
    ::PullRequest.exclude_pending.open.for_repo_github_id(repository_id)
  end

  def pull_requests_with_matching_dependabot_commit
    pull_requests_for_repo.where(dependabot_commit_sha: commit_sha)
  end

  def pull_requests_with_matching_head_commit
    pull_requests_for_repo.where(head_commit_sha: commit_sha)
  end

  def pull_requests_with_matching_base_commit
    # Don't update the base commit status after the base commit status is in a terminal state.
    # `UpdatePullRequestCiStatusJob` will only update the status to one of SUCCESS, FAILURE, or PENDING.
    # Updating value after it's first been set gives indeterminate results for the compatibility score,
    # which is a point-in-time "did this PR pass CI at the time of the last commit?" check.
    pull_requests_for_repo.
      where(base_commit_sha: commit_sha).
      where(
        "base_commit_ci_status IS NULL OR base_commit_ci_status NOT IN (?)",
        [GitHub::CheckRun::Conclusion::SUCCESS, GitHub::CheckRun::Conclusion::FAILURE]
      )
  end

  def repository
    return @repository if defined?(@repository)

    @repository = Repo.active.find_by(github_id: repository_id)
  end
end
