# frozen_string_literal: true

class RemediateAccountAndRepoActivationJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  retry_on RemediateAccountAndRepoActivation::RepoNotAccessible

  # Perform account and repository creation and enqueue config file checking
  #
  # @param github_repo_id [Integer] the GitHub ID of the repository to create the new Repo object from
  # @param github_account_id [Integer] the GitHub ID of the account which owns the new Repo object
  # @param skip_jobs [Boolean] true if config file detection should not trigger jobs
  # @param sha [String,nil] the SHA that has triggered the Repository creation event, if known
  # @return [void]
  # rubocop:disable Metrics/MethodLength
  def perform(github_repo_id:, github_account_id:, event_source:, skip_jobs: false, sha: nil)
    Dependabot::Exceptions.push(
      "gh.owner.id": github_account_id,
      "gh.repo.id": github_repo_id,
      "gh.dependabot_api.event.source": event_source,
    )

    remedy = RemediateAccountAndRepoActivation.new(
      github_repo_id: github_repo_id,
      github_account_id: github_account_id,
      event_source: event_source,
    )
    return unless remediation_still_necessary?(remedy)

    repo = remedy.run

    ResyncRepoConfigFileJob.perform_later(
      account: repo.account,
      repo_name: repo.name,
      repo_github_id: repo.github_id,
      skip_jobs: skip_jobs,
      event_source: event_source,
    )

    return unless sha

    # If we are reacting to a push, we should also perform a config file
    # Check Run on the given sha
    ValidateConfigFileJob.perform_later(
      account: repo.account,
      repo_github_id: repo.github_id,
      sha: sha,
    )
  end
  # rubocop:enable Metrics/MethodLength

  def remediation_still_necessary?(remedy)
    return true if remedy.necessary?

    Dependabot::Logger.info(
      "gh.owner.id": remedy.github_account_id,
      "gh.repo.id": remedy.github_repo_id,
      "code.namespace": self.class.name.to_s,
      "gh.dependabot_api.event.source": remedy.event_source,
      msg: "Remediation no longer needed"
    )
    false
  end
end
