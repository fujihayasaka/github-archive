# frozen_string_literal: true

require "github_helpers"

class UpdatePullRequestCiStatus
  include GitHub::Twirp::DependabotPullRequests::Helpers
  extend GitHub::Twirp::DependabotPullRequests::Helpers

  CI_STATUS_MAP = {
    resolve_ci_status_symbol(CiStatus::CI_STATUS_PENDING) => GitHub::CheckRun::Status::PENDING,
    resolve_ci_status_symbol(CiStatus::CI_STATUS_FAILURE) => GitHub::CheckRun::Conclusion::FAILURE,
    resolve_ci_status_symbol(CiStatus::CI_STATUS_SUCCESS) => GitHub::CheckRun::Conclusion::SUCCESS,
  }.freeze

  def initialize(pull_request:, refs_to_check:)
    @pr = pull_request
    @refs_to_check = refs_to_check
  end

  def run
    ActiveRecord::Base.connected_to(role: :reading) do
      return unless repo.account.active?

      pr.reload
      return if pr.pending?

      pr_updates = {}
      pr_updates.merge!(update_base_commit_ci_status_if_necessary)
      pr_updates.merge!(update_dependabot_commit_ci_status_if_necessary)
      pr_updates.merge!(update_head_commit_ci_status_if_necessary)
      update_pr_record(pr_updates) if pr_updates.any?

      update_repo_has_ci_if_necessary
    end
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: repo,
      event_source: "action.update_pull_request_ci_status",
    ).run
  rescue ActiveRecord::RecordInvalid
    active_record_log
    raise
  end

  private

  attr_reader :pr, :refs_to_check

  def active_record_log
    Dependabot::Logger.error(
      msg: "Update CI Status Failed",
      "gh.dependabot_api.pull_request.id": pr.id,
      "gh.dependabot_api.pull_request.status": pr.current_state,
      "gh.dependabot_api.pull_request.head_commit": pr.head_commit_sha,
      "gh.dependabot_api.pull_request.dependabot_commit": pr.dependabot_commit_sha,
      "gh.dependabot_api.pull_request.github_number": pr.github_number,
      "gh.dependabot_api.pull_request.persisted": pr.persisted?,
      "refs_to_check": refs_to_check
    )
  end

  def update_pr_record(updates)
    pr_id = pr.id
    ActiveRecord::Base.connected_to(role: :writing) do
      PullRequest.transaction do
        PullRequest.lock.find(pr_id).update!(updates)
      end
    end
  end

  def update_base_commit_ci_status_if_necessary
    return {} unless refs_to_check.include?(pr.base_commit_sha)

    status = cached_commit_status(pr.base_commit_sha)
    return {} if status.nil?

    { base_commit_ci_status: status }
  end

  def update_head_commit_ci_status_if_necessary
    return {} unless refs_to_check.include?(pr.head_commit_sha)
    return {} unless ci_statuses.key?(pr.head_commit_sha)

    { head_commit_ci_status: ci_statuses[pr.head_commit_sha] }
  end

  def update_dependabot_commit_ci_status_if_necessary
    return {} unless refs_to_check.include?(pr.dependabot_commit_sha)
    return {} unless ci_statuses.key?(pr.dependabot_commit_sha)

    { dependabot_commit_ci_status: ci_statuses[pr.dependabot_commit_sha] }
  end

  def update_repo_has_ci_if_necessary
    pr.reload
    return if pr.base_commit_ci_status.nil? &&
              pr.head_commit_ci_status.nil? &&
              pr.dependabot_commit_ci_status.nil?
    return if repo.has_ci?

    repo_id = repo.id

    ActiveRecord::Base.connected_to(role: :writing) do
      Repo.transaction do
        Repo.lock.find(repo_id).update!(has_ci: true)
      end
    end
  end

  def cached_commit_status(sha)
    cache_key = "commit_status/#{repo.github_id}/#{sha}"
    status = Rails.cache.fetch(cache_key)
    return status if status

    return unless ci_statuses.key?(sha)

    status = ci_statuses[sha]

    if status == GitHub::CheckRun::Conclusion::SUCCESS
      # Only cache "success" statuses. Any others might change.
      Rails.cache.write(cache_key, status, expires_in: 1.week)
    end

    status
  end

  def ci_statuses
    @ci_statuses ||= begin
      shas = refs_to_check & [pr.head_commit_sha, pr.base_commit_sha, pr.dependabot_commit_sha]
      pull_requests_client.
        get_ci_status(repo:, shas: shas.uniq).
        transform_values { |v| CI_STATUS_MAP[v] }
    end
  end

  def pull_requests_client
    @pull_requests_client ||=
      GitHub::Twirp::DependabotPullRequests.new(
        client: Dependabot::Application.github_twirp_client,
        tenant: repo.account.tenant
      )
  end

  def repo
    @repo ||= Repo.eager_load(:account).find(pr.repo_id)
  end
end
