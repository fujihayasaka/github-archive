# frozen_string_literal: true

class MergePullRequestJob < ApplicationJob
  include GitHub::Twirp::DependabotPullRequests::Helpers

  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
        GitHub::Twirp::DependabotPullRequests::TransientServiceError,
        GitHub::Twirp::DependabotPullRequests::TransientTwirpError,
        # Sometimes GitHub serves these with no explanation
        Octokit::Unauthorized,
      ],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  MINIMUM_WAIT_BEFORE_MERGE = 60.seconds

  # rubocop:disable Metrics/PerceivedComplexity
  def perform(pull_request:)
    @pull_request = pull_request

    # Using new auto-merge functionality, there's no reason to merge the PR, it will already be done.
    return if pull_request.repo.config_feature_enabled?(:new_merge_command)

    return log_doesnt_want_merge unless merge_requested?
    return handle_not_up_to_date unless pull_request.in_state?(:up_to_date)
    return log_not_active unless pull_request.repo.account.active?
    return handle_ci_not_successful unless ci_passing? || (no_ci? && merge_requested?)
    return enqueue_for_later unless pr_updated_long_enough_ago?

    MergePullRequest.new(
      pull_request: pull_request,
      require_up_to_date: true,
    ).run
  rescue MergePullRequest::MergeNotPossible => e
    create_merge_not_possible_comment(e)
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "job.merge_pull_request",
    ).run
  end
  # rubocop:enable Metrics/PerceivedComplexity

  private

  attr_reader :pull_request

  def ci_passing?
    ci_status == resolve_ci_status_symbol(CiStatus::CI_STATUS_SUCCESS)
  end

  def no_ci?
    ci_status.blank?
  end

  def ci_status
    @ci_status ||= pull_requests_client.
                   get_ci_status(repo: pull_request.repo, shas: [pull_request.head_commit_sha]).
                   fetch(pull_request.head_commit_sha, nil)
  end

  def merge_requested?
    pull_request.merge_requested?
  end

  def pr_has_been_edited?
    PullRequestCommits.new(pull_request: pull_request).
      pr_has_been_edited?(head_sha: github_details.head.sha)
  end

  def pr_updated_long_enough_ago?
    earliest_merge_time_for_cutoff < Time.now.utc
  end

  def create_merge_not_possible_comment(error)
    msg = "Dependabot tried to merge this PR, but received the following "\
          "error from GitHub:\n\n"\
          "```\n" \
          "#{error.message}\n"\
          "```"
    return if last_comment&.body == msg

    add_comment_to_pull_request(msg)
  end

  def add_comment_to_pull_request(message)
    CreateComment.new(pull_request: pull_request, comment_body: message).run
  end

  def github_details
    @github_details ||=
      installation_github_client.pull_request(
        pull_request.repo.github_id,
        pull_request.github_number,
      )
  end

  def last_comment
    @last_comment ||=
      installation_github_client.issue_comments(
        pull_request.repo.github_id,
        pull_request.github_number,
        per_page: 100,
      ).max_by(&:created_at)
  end

  def log_doesnt_want_merge
    log_info("Pull request did not request a merge.")
  end

  def handle_not_up_to_date
    log_info(
      "Pull request is not up-to-date.",
      current_state: pull_request.current_state
    )
  end

  def log_not_active
    log_info(
      "Account is not active.",
    )
  end

  def handle_ci_not_successful
    log_info(
      "Combined status for pull request is not success. Not auto-merging.",
      ci_passing: ci_passing?,
      no_ci: no_ci?,
    )
  end

  def log_edited
    log_info("Pull request has been edited. Not auto-merging.")
  end

  def log_info(message, **extras)
    Dependabot::Logger.info(
      msg: message,
      "code.namespace": "MergePullRequestJob",
      merge_requested: pull_request.merge_requested?,
      **pull_request.telemetry_attributes,
      **extras,
    )
  end

  def enqueue_for_later
    MergePullRequestJob.
      set(wait_until: earliest_merge_time_for_cutoff).
      perform_later(pull_request: pull_request)
  end

  def earliest_merge_time_for_cutoff
    [
      pull_request.created_at,
      pull_request.last_transition&.created_at,
    ].compact.max + MINIMUM_WAIT_BEFORE_MERGE
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: pull_request.repo.account)
  end

  def uncache_installation_client
    GitHubHelpers.delete_cached_access_token_for(
      account: pull_request.repo.account,
    )
    @installation_github_client = nil
  end

  def pull_requests_client
    @pull_requests_client ||=
      GitHub::Twirp::DependabotPullRequests.new(
        client: Dependabot::Application.github_twirp_client,
        tenant: pull_request.repo.account.tenant
      )
  end
end
