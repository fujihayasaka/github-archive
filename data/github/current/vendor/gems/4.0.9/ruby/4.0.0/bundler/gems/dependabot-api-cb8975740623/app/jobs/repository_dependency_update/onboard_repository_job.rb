# frozen_string_literal: true

# When our VulnerabilityAlertProcessor ingests a message from a Repository
# we have not seen before, we need to tolerate replica lag before it is
# available via the API for the provided installation id
#
# This class attempts to wait for a healthy installation before calling
# VulnerabilityAlertProcessor#create_security_update_job to continue
# with the process.
module RepositoryDependencyUpdate
  class OnboardRepositoryJob < ApplicationJob
    queue_as :default
    default_retries_for_idempotent_jobs

    class InstallationNotFound < StandardError; end
    class InstallationCannotAccessRepo < StandardError; end

    T.unsafe(self).include ActiveJob::Retry.new(
      strategy: RateLimitBackoffStrategy.new(
        limit: 5,
        retryable_exceptions: [
          *GitHubHelpers::RETRYABLE_ERRORS,
          InstallationNotFound,
          InstallationCannotAccessRepo,
        ],
      ),
    )

    def perform(dependency_update:, advisory:, user:, repository:)
      Dependabot::Exceptions.push(
        "gh.owner.id": user.id,
        "gh.repo.id": repository.id,
      )

      verify_ready_to_onboard_repo!(user, repository) unless repository.exists?

      VulnerabilityAlertHandler.new(
        dependency_update: dependency_update,
        advisory: advisory,
        user: user,
        repository: repository
      ).create_security_update_job
    end

    private

    def verify_ready_to_onboard_repo!(user, repository)
      if onboard_with_global_app?(user)
        SetupAccountWithGlobalApp.new(
          github_id: user.id,
          tenant_id: user.tenant_id,
          tenant_slug: user.tenant_slug,
          event_source: "job.onboard_repository",
        ).run
      else
        verify_install_is_ready!(user, repository)
      end
    end

    def onboard_with_global_app?(user)
      account = Account.find_by(github_id: user.id)

      return true if account.nil? && GitHubHelpers.onboard_account_with_global_app?(github_id: user.id)

      account&.using_global_app? == true
    end

    # We do not cache nil installation_access_tokens in the event of an error so there is no need
    # to cache bust between retries.
    def verify_install_is_ready!(user, repository)
      GitHubHelpers.installation_access_token_for(user.installation_id, repo_ids: [repository.id])
    rescue GitHubHelpers::InvalidInstallationId
      raise InstallationNotFound,
            "Dependabot is not installed on #{user.type} ID #{user.id}"
    rescue Octokit::UnprocessableEntity
      raise InstallationCannotAccessRepo,
            "Dependabot installation on #{user.type} ID #{user.id} cannot access Repository ID #{repository.id}"
    end
  end
end
