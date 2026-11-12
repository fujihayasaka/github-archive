# frozen_string_literal: true

require "github_helpers"

# Wrapper for resyncing a repo's config file. Doing this in a job allows us
# to retry any exceptions from GitHub (server errors or connection failures).
class ResyncRepoConfigFileJob < ApplicationJob
  queue_as :default

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
        Octokit::Unauthorized,
      ],
    ),
    callback: proc do |e, _|
      next unless e.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  rescue_from(StandardError) do |e|
    log_error(e)
    raise
  end

  default_retries_for_idempotent_jobs do |job_with_no_more_retries, error|
    job_with_no_more_retries.log_error(error)
    raise
  end

  # rubocop:disable Metrics/MethodLength
  def perform(account:, repo_name:, repo_github_id:, skip_jobs: false, event_source: "unknown")
    @account = account
    @repo_name = repo_name
    @repo_github_id = repo_github_id
    @event_source = event_source

    Dependabot::Exceptions.push(
      "gh.owner.id": account.github_id,
      "gh.repo.id": repo_github_id
    )

    ProcessConfigFile.new(
      account: account,
      repo_name: repo_name,
      repo_github_id: repo_github_id,
      quiet: skip_jobs,
      event_source: event_source,
    ).run
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.message.include?("Directory has already been taken")

    Dependabot::Logger.info(
      msg: "Duplicate directory detected in config file, resyncing entire repo.",
      "code.namespace": "ResyncRepoConfigFileJob",
      "exception.type": e.class.to_s,
      "exception.message": e.message,
      "gh.owner.id": account.github_id,
      "gh.repo.id": repo_github_id,
      "gh.repo.name": repo_name,
      "gh.dependabot_api.event.source": event_source,
    )

    # There's most likely a duplicate directory in a security UpdateConfig,
    # resync the entire repo to fix it.
    Stafftools::ResyncRepoJob.perform_later(account: account, github_id: repo_github_id)
  end
  # rubocop:enable Metrics/MethodLength

  def log_error(error)
    github_repo_id = arguments[0][:repo_github_id]

    Dependabot::Logger.info(
      msg: "unable to synchronize config file.",
      "code.namespace": "ResyncRepoConfigFileJob",
      "exception.type": error.class.to_s,
      "exception.message": error.message,
      "gh.repo.id": github_repo_id,
      "gh.dependabot_api.event.source": event_source,
    )
  end

  private

  attr_reader :account, :repo_name, :repo_github_id, :event_source

  def uncache_installation_client
    GitHubHelpers.delete_cached_access_token_for(
      account: account,
    )
  end
end
