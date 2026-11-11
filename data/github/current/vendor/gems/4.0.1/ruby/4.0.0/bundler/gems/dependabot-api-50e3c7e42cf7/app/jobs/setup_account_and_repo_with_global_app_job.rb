# frozen_string_literal: true

class SetupAccountAndRepoWithGlobalAppJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  retry_on(*GitHubHelpers::RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5)

  # Perform account setup and then enqueue repository creation and config file checking
  #
  # @param account_github_id [Integer] the GitHub ID of the account which owns the repository
  # @param repo_github_id [Integer] the GitHub ID of the repository to create the new Repo object from
  # @param tenant_id [Integer,String] the GitHub ID of the tenant that owns the repo
  # @param tenant_slug [String] the GitHub short name of the tenant that owns the repo
  # @param event_source [String] the source of the event that triggered the creation
  # @param sha [String,nil] the SHA that has triggered the Repository creation event, if known
  # @return [void]
  def perform(account_github_id:, repo_github_id:, tenant_id:, tenant_slug:, event_source:, sha: nil)
    Dependabot::Exceptions.push(
      "gh.owner.id": account_github_id,
      "gh.repo.id": repo_github_id,
    )

    account = SetupAccountWithGlobalApp.new(
      github_id: account_github_id,
      tenant_id: tenant_id,
      tenant_slug: tenant_slug,
      event_source: event_source
    ).run

    SetupRepoJob.perform_later(account: account, github_id: repo_github_id, sha: sha)
  end
end
