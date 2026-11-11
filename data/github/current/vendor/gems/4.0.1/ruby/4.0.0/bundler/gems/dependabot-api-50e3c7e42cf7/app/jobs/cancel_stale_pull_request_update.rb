# frozen_string_literal: true

require "github_helpers"

class CancelStalePullRequestUpdate < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
        # Sometimes GitHub serves these with no explanation
        Octokit::Unauthorized,
      ],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  def perform(update_job:, comment_on_pr: true)
    @update_job = update_job

    return unless pull_request && pull_request_is_stuck_in_updating?

    pull_request.transition_to!(:up_to_date)

    return unless pull_request.account.active?

    remove_pr_message_addendum
    add_apology_comment if comment_on_pr
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "job.cancel_stale_pull_request_update",
    ).run
  end

  private

  attr_reader :update_job

  def remove_pr_message_addendum
    # Remove the "Dependabot is rebasing this PR" comment, if present.
    regex = %r{\[//\]: # \(dependabot-start\).*\[//\]: # \(dependabot-end\)}m
    updated_body = github_details.body.gsub(regex, "").strip

    UpdatePullRequestBody.new(
      pull_request: pull_request,
      updated_body: updated_body,
    ).run
  end

  def add_apology_comment
    msg = if %w(user_error expected_error).include?(update_job.job_metric_error_category)
            "#{update_job.last_error.error_presenter.issue_title}. " \
            "Because of this, Dependabot cannot update this pull request."
          else
            "Dependabot tried to update this pull request, but something went "\
            "wrong. We're looking into it, but in the meantime you can retry "\
            "the update by commenting `@dependabot recreate`."
          end

    CreateComment.new(pull_request: pull_request, comment_body: msg).run
  end

  def pull_request
    @pull_request ||= update_job&.pull_request_transition&.pull_request
  end

  def pull_request_is_stuck_in_updating?
    pull_request.last_transition == update_job.pull_request_transition
  end

  def github_details
    @github_details ||= fetch_pull_request_from_github
  end

  def fetch_pull_request_from_github
    installation_github_client.pull_request(
      pull_request.repo.github_id,
      pull_request.github_number,
    )
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.new(
        account: pull_request.repo.account,
      )
  end

  def uncache_installation_client
    GitHubHelpers.delete_cached_access_token_for(
      account: pull_request.repo.account,
    )
    @installation_github_client = nil
  end
end
