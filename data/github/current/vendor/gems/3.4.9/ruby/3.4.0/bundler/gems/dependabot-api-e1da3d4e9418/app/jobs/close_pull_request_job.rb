# frozen_string_literal: true

# Wrapper for closing update config issues on GitHub. Doing this in a job allows
# us to retry any exceptions from GitHub (server errors or connection failures).
class ClosePullRequestJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  DEPENDENCY_GROUP_CLOSE_REASONS = {
    "dependency_group_deleted" => "The group that created this PR has been removed from your configuration.",
    "dependency_group_empty" => "None of your dependencies match this group anymore, " \
                                "you may need to update your configuration file to remove it or change its rules.",
  }.freeze

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions:
        [
          *GitHubHelpers::RETRYABLE_ERRORS,
          Octokit::Unauthorized,
          ClosePullRequest::GitHubCloseBug,
        ],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  def perform(pull_request:, reason: nil, comment_on_pr: true)
    @pull_request = pull_request
    @reason = reason
    @comment_on_pr = comment_on_pr

    raise ArgumentError, "provide a reason or set comment_on_pr to false" if comment_on_pr? && reason.nil?

    return unless pull_request.repo.account.active?

    create_comment unless pr_closed_on_github? || !comment_on_pr?

    ClosePullRequest.new(pull_request: pull_request).run
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "job.close_pull_request",
    ).run
  rescue ClosePullRequest::GitHubCloseBug => e
    handle_github_close_bug(e)
  end

  private

  attr_reader :pull_request, :reason

  def pr_closed_on_github?
    github_details.state == "closed"
  end

  def comment_on_pr?
    @comment_on_pr
  end

  def create_comment
    comment_body = if DEPENDENCY_GROUP_CLOSE_REASONS.key?(reason)
                     group_change_comment
                   else
                     dependency_change_comment
                   end

    CreateComment.new(
      pull_request: pull_request,
      comment_body: comment_body,
    ).run
  end

  def dependency_change_comment
    dependency_names =
      if pull_request.single_dependency?
        "#{pull_request.updated_dependencies.first.name} is"
      else
        "these dependencies are"
      end

    reason_text =
      case reason
      when "dependency_removed", "dependencies_removed" then "no longer a dependency"
      when "up_to_date" then "up-to-date now"
      when "update_no_longer_possible" then "no longer updatable"
      when "dependency_ignored" then "no longer being updated by Dependabot"
      when "dependencies_changed" then "updatable in another way"
      else raise "Unexpected reason to close PR: #{reason}"
      end

    "Looks like #{dependency_names} #{reason_text}, so this is no longer needed."
  end

  def group_change_comment
    DEPENDENCY_GROUP_CLOSE_REASONS.fetch(reason)
  end

  def handle_github_close_bug(error)
    raise error unless comment_on_pr?

    self.class.
      set(wait: 1.second).
      perform_later(pull_request: pull_request, comment_on_pr: false)
  end

  def github_details
    @github_details ||=
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
