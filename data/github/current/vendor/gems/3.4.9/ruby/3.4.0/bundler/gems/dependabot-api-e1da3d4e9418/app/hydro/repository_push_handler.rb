# frozen_string_literal: true

class RepositoryPushHandler
  attr_reader :ref, :before_sha, :after_sha, :repository, :owner, :changed_files

  def self.run(message)
    ref = message.value.fetch(:ref)
    before_sha = message.value.fetch(:before)
    after_sha = message.value.fetch(:after)
    repository = message.value.fetch(:repository)
    owner = message.value.fetch(:owner)
    changed_files = message.value.fetch(:changed_files)

    new(ref, before_sha, after_sha, repository, owner, changed_files).run
  end

  # rubocop:disable Metrics/ParameterLists
  def initialize(ref, before_sha, after_sha, repository, owner, changed_files)
    @ref = ref
    @before_sha = before_sha
    @after_sha = after_sha
    @repository = repository
    @owner = owner
    @changed_files = changed_files
  end
  # rubocop:enable Metrics/ParameterLists

  def run
    return unless repo

    Dependabot::Exceptions.push(
      "gh.owner.id": repo.account.github_id,
      "gh.repo.id": repo.github_id,
    )

    update_pull_request_head_commits

    return unless affected_configs.any?
    return unless default_branch? || target_branch?
    return unless active_repo?

    update_repo

    # When a Repository is paused we still update Pull Request and Repository
    # information in our data objects to avoid them becoming out of sync but
    # we do not propagate any rebases or retries.
    return if repo.paused?

    update_dependabot_pull_requests
  end

  private

  def update_pull_request_head_commits
    return unless ref.match?(%r{^refs/heads/\h{4}?dependabot[/-]})
    return unless repo

    raise "Missing before_sha" unless before_sha
    raise "Missing after_sha" unless after_sha

    # GitHub sends us these when a branch is deleted
    return if after_sha == "0000000000000000000000000000000000000000"

    updatable_pull_request_ids = repo.pull_requests.exclude_pending.where(head_commit_sha: before_sha).pluck(:id)
    # update the head SHA for the entire batch of PR's in a single DB call
    ::PullRequest.where(id: updatable_pull_request_ids).update_all(head_commit_sha: after_sha)

    updatable_pull_request_ids.each do |id|
      UpdatePullRequestCiStatusJob.perform_later(
        pull_request_id: id,
        refs_to_check: [after_sha],
      )
    end
  end

  # TODO: Handle ownership transfer?
  #
  # We currently handle transfers in two places:
  # - SynchronizeRepoState
  # - ProcessConfigFile
  #
  # SynchronizeRepoState is generally used reactively when we detect an issue
  # and ProcessConfigFile only helps a subset of users. Pushes seem like an
  # opportunity to handle this more proactively for all users.
  def update_repo
    repo.update!(
      name: repository[:name],
      default_branch: repository[:default_branch],
      private: repository[:visibility] != "PUBLIC",
      primary_language: repository[:primary_language_name]&.downcase,
    )
  end

  def default_branch?
    ref.sub(%r{^refs/heads/}, "") == repository[:default_branch]
  end

  def target_branch?
    return unless repo

    target_branches = repo.active_update_configs.pluck(:target_branch).uniq
    target_branches.include?(ref.sub(%r{^refs/heads/}, ""))
  end

  def changed_file_paths
    @changed_file_paths ||= changed_files.flat_map do |f|
      [f[:current_path], f[:previous_path]]
    end.uniq
  end

  def active_repo?
    repo && repo.active_update_configs.any?
  end

  def affected_update_config_ids
    @affected_update_config_ids ||= affected_configs.map(&:id).to_set
  end

  def affected_configs
    @affected_configs ||= repo.active_update_configs.select do |config|
      normalized_monitored_file_paths = Array(config.monitored_files).map { |path| path.delete_prefix("/") }
      changed_file_paths.intersect?(normalized_monitored_file_paths)
    end
  end

  def repo
    @repo ||= Repo.preload(:account, :active_update_configs).
              find_by(github_id: repository[:id])
  end

  def update_dependabot_pull_requests
    return if affected_update_config_ids.empty?

    repo.pull_requests.open.where(update_config_id: affected_update_config_ids).
      each_with_index do |pr, index|
        enqueue_pr_update(pr, wait: index)
      end
  end

  def enqueue_pr_update(pull_request, wait:)
    CheckPullRequestForConflictsJob.
      set(wait: wait.seconds).
      perform_later(
        pull_request: pull_request,
        event_source: "hydro.repository_push",
        manual: false,
      )
  end
end
