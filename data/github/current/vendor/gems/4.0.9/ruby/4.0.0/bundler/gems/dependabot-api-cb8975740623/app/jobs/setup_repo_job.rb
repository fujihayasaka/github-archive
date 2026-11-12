# frozen_string_literal: true

# Setup a Repo object from the GitHub API with tolerance for race condtions
# where the Account's credentials do not include the given #github_repo_id
# at execution time.
#
# This job calls FindOrCreateRepo which handles:
#  - Creation of new Repos
#  - Updating of existing Repos
#  - Transferral of Repos from one Account to another
#
# It then triggers a synchronisation of the Repo's associated UpdateConfigs with
# any Dependabot configuration file in the repository.
#
# Finally, if optionally provided a `sha` it will validate any existing configuration
# file in the repository at that reference and push a pass/fail check to GitHub.
#
class SetupRepoJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 5,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
        Dependabot::ResourceUnavailableToInstallation,
        Octokit::Unauthorized,
        Octokit::NotFound,
        Octokit::RepositoryUnavailable,
      ],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      account = arguments[0][:account]
      uncache_installation_client(account)
    end,
  )

  # If we exhaust retries without being able to find the Repository, it's likely
  # the user is spammy and their API usage is restricted
  #
  # TODO: cleanly offboard 'spammy' users https://github.com/github/dependabot-updates/issues/963
  rescue_from(Octokit::NotFound) do |_error|
    account = arguments[0][:account]
    github_repo_id = arguments[0][:github_id]

    Dependabot::Logger.info(
      msg: "repo not found",
      "code.namespace": "SetupRepoJob",
      "gh.owner.id": account.github_id,
      "gh.repo.id": github_repo_id,
    )
  end

  rescue_from(Octokit::RepositoryUnavailable) do |error|
    account = arguments[0][:account]
    github_repo_id = arguments[0][:github_id]

    Dependabot::Logger.info(
      "exception.message": error.message,
      "code.namespace": "SetupRepoJob",
      "gh.owner.id": account.github_id,
      "gh.repo.id": github_repo_id,
    )
  end

  # Perform a repository creation and enqueue config file checking
  #
  # @param account [Account] the Dependabot Account which owns the new Repo object
  # @param github_id [Integer] the GitHub ID of the repository to create the new Repo object from
  # @param sha [String,nil] the SHA that has triggered the Repository creation event, if known
  # @return [void]
  # rubocop:disable Metrics/MethodLength
  def perform(account:, github_id:, sha: nil)
    Dependabot::Exceptions.push(
      "gh.owner.id": account.github_id,
      "gh.repo.id": github_id
    )

    return unless account.active?

    repo_details = fetch_repo_details(account: account, github_id: github_id)
    return unless repo_details

    repo = FindOrCreateRepo.new(github_repo: repo_details).run
    repo_settings = Dependabot::Application.dependabot_repository_settings_client.get_repository_settings(repo)
    repo.update!(
      security_updates_enabled: repo_settings.automated_security_updates_enabled,
    )

    skip_jobs = if repo.monolith_feature_enabled?(:dependabot_skip_jobs_on_new_repos)
                  Time.current - repo_details["created_at"] < 1.hour
                else
                  false
                end

    ResyncRepoConfigFileJob.perform_later(
      account: account,
      repo_name: repo.name,
      repo_github_id: repo.github_id,
      skip_jobs: skip_jobs,
      event_source: "setup_repo_job",
    )

    MetricsClient.increment("setup_repository", tags: { fork: repo_details.fetch(:fork) { false } })

    return unless sha

    # If we are reacting to a push, we should also perform a config file
    # Check Run on the given sha
    ValidateConfigFileJob.perform_later(
      account: account,
      repo_github_id: repo.github_id,
      sha: sha,
    )
  end
  # rubocop:enable Metrics/MethodLength

  def fetch_repo_details(account:, github_id:)
    client = GitHubHelpers::ClientWithRetries.new(account: account)
    client.repo(github_id)
  rescue Octokit::UnavailableForLegalReasons
    nil
  end

  def uncache_installation_client(account)
    return unless account.current_installation_id

    GitHubHelpers.delete_cached_access_token_for(
      account: account,
    )
  end
end
