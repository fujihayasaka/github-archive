# frozen_string_literal: true

require "github_helpers"

class TransferRepoAccountJob < ApplicationJob
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

      uncache_installation_clients
    end,
  )

  def perform(repo:, new_account:)
    @repo = repo
    @new_account = new_account

    # If the repo has already been updated this is a no-op
    return if repo.account == new_account

    # NOTE: Silently ignore any issues fetching the old or new repo details as
    # this can be a transient error and will eventually be handled by
    # SynchronizeRepoState
    if github_repo_details.nil?
      MetricsClient.increment("transfer_repo_account.repo_not_found")
      return
    end

    # Otherwise, look for the current account using the fetched details
    current_account = Account.find_by(
      github_id: github_repo_details.owner.id,
      account_type: current_account_type,
    )

    # If the current account isn't in our database, disable the repo. If it is,
    # update the repo to use it (may be a no-op, but that's fine).
    if current_account.nil?
      deactivate_repo
    else
      repo.update!(account: current_account)
    end
  end

  private

  attr_reader :repo, :new_account

  def deactivate_repo
    return unless repo.active?

    DeactivateRepo.new(repo_github_id: repo.github_id).run
  end

  def github_repo_details
    return @github_repo_details if defined?(@github_repo_details)

    @github_repo_details =
      github_repo_details_using_new_install ||
      github_repo_details_using_old_install
  end

  def current_account_type
    case github_repo_details.owner.type
    when "User" then "user"
    when "Organization" then "org"
    end
  end

  def github_repo_details_using_new_install
    new_installation_github_client&.repo(repo.github_id)
  rescue Octokit::NotFound, GitHubHelpers::InvalidInstallationId
    nil
  end

  def github_repo_details_using_old_install
    old_installation_github_client&.repo(repo.github_id)
  rescue Octokit::NotFound, GitHubHelpers::InvalidInstallationId
    nil
  end

  def new_installation_github_client
    return unless new_account&.current_installation_id

    @new_installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: new_account)
  end

  def old_installation_github_client
    @old_installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: repo.account)
  end

  def uncache_installation_clients
    if new_account&.current_installation_id
      GitHubHelpers.delete_cached_access_token_for(
        account: new_account,
      )
    end

    if repo.account.current_installation_id
      GitHubHelpers.delete_cached_access_token_for(
        account: repo.account,
      )
    end

    @new_installation_github_client = nil
    @old_installation_github_client = nil
  end
end
