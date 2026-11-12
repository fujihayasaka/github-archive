# frozen_string_literal: true

# Validates a Dependabot Configuration file that is reachable
# from the GitHub API for the associated Account
#
# Preconditions:
#   - The repository associated with the repo_github_id must exist in our database
#   - The repository associated with the repo_github_id must belong to the given account
class ValidateConfigFileJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 3,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
      ],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  def perform(account:, repo_github_id:, sha:)
    @account = account
    return unless @account.active?

    repo = account.repos.find_by!(github_id: repo_github_id)

    ValidateConfigFile.new(repo: repo, sha: sha).run
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    return unless repo

    SynchronizeRepoState.new(
      repo: repo,
      event_source: "job.validate_config_file",
    ).run
  end

  private

  attr_reader :account

  def uncache_installation_client
    return unless account.current_installation_id

    GitHubHelpers.delete_cached_access_token_for(
      account: account,
    )
  end
end
