# frozen_string_literal: true

module Stafftools
  class ResyncRepoJob < ApplicationJob
    queue_as :default
    default_retries_for_idempotent_jobs

    T.unsafe(self).include ActiveJob::Retry.new(
      strategy: RateLimitBackoffStrategy.new(
        limit: 5,
        retryable_exceptions: [
          *GitHubHelpers::RETRYABLE_ERRORS,
          Octokit::Forbidden,
          Octokit::Unauthorized,
          Octokit::NotFound,
          Octokit::UnprocessableEntity,
        ],
      ),
      callback: proc do |exception, _|
        Dependabot::Logger.error(
          msg: "ResyncRepoJob raised a retryable exception",
          "code.namespace": self.class.name.to_s,
          "gh.owner.id": account.id,
          "gh.repo.id": repo.github_id,
          "exception.type": exception.class,
          "exception.message": exception.message,
        )

        next unless exception.is_a?(Octokit::Unauthorized)

        uncache_installation_client
      end,
    )

    # Resynchronises a repository's details from GitHub, if successful checks for and parses
    # any config file present in the `.github/` on the default branch
    #
    # @param account [Account] the Dependabot Account which owns the new Repo object
    # @param github_id [Integer] the GitHub ID of the repository to create the new Repo object from
    # @return [void]
    def perform(account:, github_id:)
      @account = account

      Dependabot::Exceptions.push(
        "gh.owner.id": account.id,
        "gh.repo.id": github_id
      )
      @repo = account.repos.preload(:active_update_configs).find_by(github_id: github_id)

      process_config_file if synchronize_repo_state.success?
    end

    private

    attr_reader :account, :repo

    def synchronize_repo_state
      SynchronizeRepoState.new(
        repo: repo,
        event_source: "stafftools_resync_repo_job"
      ).run
    end

    # Process the config file without triggering any UpdateJobs
    def process_config_file
      ProcessConfigFile.new(
        account: repo.account,
        repo_name: repo.name,
        repo_github_id: repo.github_id,
        quiet: true,
        event_source: "stafftools_resync_repo_job",
      ).run
    end

    def uncache_installation_client
      return unless account.current_installation_id

      GitHubHelpers.delete_cached_access_token_for(
        account: account,
      )
    end
  end
end
