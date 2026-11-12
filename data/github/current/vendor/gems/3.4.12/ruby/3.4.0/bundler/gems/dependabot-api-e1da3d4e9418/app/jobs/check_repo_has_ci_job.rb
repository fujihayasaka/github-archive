# frozen_string_literal: true

# Delegates to the CheckRepoHasCi action. Useful to have as a job as
# it allows us to retry GitHub errors straightforwardly
class CheckRepoHasCiJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
        GitHubGraphQL::ServerError,
        GitHubGraphQL::UnauthorizedError,
        GitHubGraphQL::RateLimited,
      ],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(GitHubGraphQL::UnauthorizedError)

      uncache_installation_client
    end,
  )

  def perform(repo:)
    @repo = repo
    ::Dependabot::Exceptions.push(repo.telemetry_attributes)
    CheckRepoHasCi.new(repo: repo).run
  end

  private

  attr_reader :repo

  def uncache_installation_client
    return unless repo.account.current_installation_id

    GitHubHelpers.delete_cached_access_token_for(
      account: repo.account,
    )
  end
end
