# frozen_string_literal: true

class RepositoryCommitStatusCreatedHandler
  attr_reader :commit_sha, :state, :branch_names, :context, :repository_id

  def self.run(message)
    commit_sha = message.value.fetch(:commit_sha)
    state = message.value.fetch(:state)
    branch_names = message.value.fetch(:branch_names)
    context = message.value.fetch(:context)
    repository_id = message.value.fetch(:repository_id)

    new(commit_sha, state, branch_names, context, repository_id).run
  end

  def initialize(commit_sha, state, branch_names, context, repository_id)
    @commit_sha = commit_sha
    @state = state
    @branch_names = branch_names
    @context = context
    @repository_id = repository_id
  end

  def run
    ActiveRecord::Base.connected_to(role: :reading) do
      return unless dependabot_branch? && active_repository?

      update_pr_ci_statuses
      enqueue_pr_merges if success?
      enqueue_failure_comment if failure? || error?
    end
  end

  private

  def success?
    state == :SUCCESS
  end

  def failure?
    state == :FAILURE
  end

  def error?
    state == :ERROR
  end

  def active_repository?
    repository.present?
  end

  def dependabot_branch?
    branch_names&.any? { |branch_name| branch_name.include?("dependabot") }
  end

  def update_pr_ci_statuses
    affected_dependabot_prs.each do |pr|
      UpdatePullRequestCiStatusJob.perform_later(
        pull_request: pr,
        refs_to_check: [commit_sha],
      )
    end
  end

  def enqueue_pr_merges
    pull_requests_awaiting_merge.each do |pr|
      MergePullRequestJob.
        set(wait_until: Time.now.utc + rand(0..60).seconds).
        perform_later(pull_request: pr)
    end
  end

  def enqueue_failure_comment
    pull_requests_awaiting_merge.each do |pr|
      CreateCheckOrStatusFailureCommentJob.perform_later(pull_request: pr)
    end
  end

  def affected_dependabot_prs
    [
      *pull_requests_with_matching_head_commit,
      *pull_requests_with_matching_base_commit,
      *pull_requests_with_matching_dependabot_commit,
    ].uniq
  end

  def pull_requests_for_repo
    ::PullRequest.exclude_pending.for_repo_github_id(repository_id)
  end

  def pull_requests_with_matching_dependabot_commit
    @pull_requests_with_matching_dependabot_commit ||=
      pull_requests_for_repo.where(
        dependabot_commit_sha: commit_sha,
      )
  end

  def pull_requests_with_matching_head_commit
    @pull_requests_with_matching_head_commit ||=
      pull_requests_for_repo.where(
        head_commit_sha: commit_sha,
      )
  end

  def pull_requests_with_matching_base_commit
    @pull_requests_with_matching_base_commit ||=
      pull_requests_for_repo.where(
        base_commit_sha: commit_sha,
      )
  end

  def pull_requests_awaiting_merge
    pull_requests_with_matching_head_commit.open.
      includes(:update_config, :updated_dependencies, :account).
      select(&:merge_requested?)
  end

  def repository
    return @repository if defined?(@repository)

    @repository = Repo.active.find_by(github_id: repository_id)
  end
end
