# frozen_string_literal: true

require "github_helpers"
require "comments/rebase"

class HandleRebaseRequestJob < ApplicationJob
  include GitHub::Telemetry::Traces::Traceable

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

  # rubocop:disable Metrics/MethodLength
  def perform(pull_request:)
    telemetry_attributes = pull_request.telemetry_attributes

    tracer.in_span("#{self.class.name}#perform", attributes: telemetry_attributes) do
      @pull_request = pull_request

      return comment_edited if pr_has_been_edited?

      if github_details.merged
        comment_merged
        enqueue_job_to_resync_pr_state_if_necessary
        return
      end

      if github_details.state == "closed"
        comment_closed
        enqueue_job_to_resync_pr_state_if_necessary
        return
      end

      Statesman::Machine.retry_conflicts { update_pull_request_if_new_commits }
    rescue *SynchronizeRepoState::HANDLED_ERRORS
      SynchronizeRepoState.new(
        repo: pull_request.repo,
        event_source: "job.handle_rebase_request",
      ).run
    end
  end
  # rubocop:enable Metrics/MethodLength

  private

  def enqueue_job_to_resync_pr_state_if_necessary
    current_state = pull_request.current_state.to_sym
    return if github_details.merged && current_state == :merged
    return if github_details.state == "closed" && current_state == :closed

    ResyncPrStateJob.perform_later(pull_request: pull_request)
  end

  def pr_has_been_edited?
    PullRequestCommits.new(pull_request: pull_request).
      pr_has_been_edited?(head_sha: github_details.head.sha)
  end

  def enqueue_job_to_resync_pr_state
    ResyncPrStateJob.perform_later(pull_request: pull_request)
  end

  def github_details
    tracer.in_span("#{self.class.name}#github_details") do
      @github_details ||=
        installation_github_client.pull_request(
          pull_request.repo.github_id,
          pull_request.github_number,
        )
    end
  end

  def update_pull_request_if_new_commits
    return comment_deleted if pull_request.update_config.in_state?(:deleted)
    return update_pull_request if github_details.mergeable_state == "behind"
    return update_pull_request if new_commits?(github_details.base.ref)
    return update_pull_request if default_branch_changed?(github_details)

    comment_already_up_to_date(github_details.base.ref)
  end

  def comment_deleted
    comment_on_pull_request(Comments::Rebase::DELETED)
  end

  def comment_edited
    comment_on_pull_request(Comments::Rebase::PULL_REQUEST_EDITED)
  end

  def comment_merged
    comment_on_pull_request(Comments::Rebase::MERGED)
  end

  def comment_closed
    comment_on_pull_request(Comments::Rebase::CLOSED)
  end

  def comment_already_up_to_date(target_branch)
    comment = "Looks like this PR is already up-to-date with "\
              "#{target_branch}! If you'd still like to recreate it "\
              "from scratch, overwriting any edits, you can request "\
              "`@dependabot recreate`."
    comment_on_pull_request(comment)
  end

  def comment_on_pull_request(comment)
    CreateComment.new(pull_request: pull_request, comment_body: comment).run
  end

  def new_commits?(target_branch)
    tracer.in_span("#{self.class.name}#.new_commits?") do
      last_commit = installation_github_client.commit(
        pull_request.repo.github_id,
        target_branch,
      )

      pull_request.base_commit_sha != last_commit.sha
    end
  rescue Octokit::UnprocessableEntity => e
    raise unless e.message.include?("No commit found")

    true
  end

  def default_branch_changed?(github_details)
    return false unless pull_request.update_config.target_branch.nil?

    github_details.base.repo.default_branch != github_details.base.ref
  end

  def update_pull_request
    EnqueueRebase.new(
      pull_request: pull_request,
      github_details: github_details,
      manual: true,
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
end
