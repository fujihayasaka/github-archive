# frozen_string_literal: true

require "github_helpers"

# This job is invoked in two contexts:
# - The owning UpdateConfig has its `target_branch` property changed in the config file
# - A Pull Request is reopened
#
# In both cases it is the responsibility of the caller to make any checks on
# whether the rebase should be performed as this job will only back off if the
# PullRequest is in the wrong state on GitHub.
#
class RebasePullRequestIfNewCommitsJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions:
        [*GitHubHelpers::RETRYABLE_ERRORS, Octokit::Unauthorized],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  attr_reader :pull_request

  def perform(pull_request:)
    @pull_request = pull_request

    return log_already_updating if pull_request.in_state?(:updating)
    return log_edited if pr_has_been_edited?

    if github_details.merged || github_details.state == "closed"
      log_merged_or_closed
      enqueue_job_to_resync_pr_state_if_necessary
      return
    end

    Statesman::Machine.retry_conflicts { update_pull_request_if_new_commits }
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "job.rebase_pull_request_if_new_commits",
    ).run
  end

  private

  def pr_has_been_edited?
    PullRequestCommits.new(pull_request: pull_request).
      pr_has_been_edited?(head_sha: github_details.head.sha)
  end

  def github_details
    @github_details ||=
      installation_github_client.pull_request(
        pull_request.repo.github_id,
        pull_request.github_number,
      )
  end

  def update_pull_request_if_new_commits
    return update_pull_request if github_details.mergeable_state == "behind"
    return update_pull_request if new_commits?(github_details.base.ref)
    return update_pull_request if default_branch_changed?(github_details)

    log_already_up_to_date
  end

  def log_edited
    Rails.logger.info(
      "Pull request #{pull_request.id} has been edited by someone other " \
      "than dependabot. Moving along...",
    )
  end

  def log_merged_or_closed
    if github_details.merged
      Rails.logger.info("Pull request #{pull_request.id} is already merged.")
    elsif github_details.state == "closed"
      Rails.logger.info("Pull request #{pull_request.id} is closed.")
    end
  end

  def log_already_updating
    Rails.logger.info(
      "Pull request #{pull_request.id} is already being updated. Ignoring.",
    )
  end

  def log_already_up_to_date
    Rails.logger.info("Pull request #{pull_request.id} is up-to-date.")
  end

  def new_commits?(target_branch)
    last_commit = installation_github_client.commit(
      pull_request.repo.github_id,
      target_branch,
    )

    pull_request.base_commit_sha != last_commit.sha
  rescue Octokit::UnprocessableEntity => e
    raise unless e.message.include?("No commit found")

    false
  end

  def default_branch_changed?(github_details)
    return false unless pull_request.update_config.target_branch.nil?

    github_details.base.repo.default_branch != github_details.base.ref
  end

  def update_pull_request
    EnqueueRebase.new(
      pull_request: pull_request,
      github_details: github_details,
    ).run
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

  def enqueue_job_to_resync_pr_state_if_necessary
    current_state = pull_request.current_state.to_sym
    return if github_details.merged && current_state == :merged
    return if github_details.state == "closed" && current_state == :closed

    ResyncPrStateJob.perform_later(pull_request: pull_request)
  end
end
