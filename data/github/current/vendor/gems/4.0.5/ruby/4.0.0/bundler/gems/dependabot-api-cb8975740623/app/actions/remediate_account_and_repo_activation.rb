# frozen_string_literal: true

require "github_helpers"

# Attempts to correct problems when an account or repo has failed to properly
# activate due to missing or failed installation triggers.
class RemediateAccountAndRepoActivation
  attr_reader :github_repo_id, :github_account_id, :event_source

  class RepoNotAccessible < StandardError; end

  def initialize(github_repo_id:, github_account_id:, event_source:)
    @github_repo_id = github_repo_id
    @github_account_id = github_account_id
    @event_source = event_source
  end

  def run
    account = find_or_create_account
    record_remediation_error(error_type: :unable_to_remediate_in_proxima) unless account

    repo = find_or_create_repo(account)
    unless repo
      record_remediation_error(error_type: :repo_null)
      raise RepoNotAccessible
    end
    repo
  rescue Octokit::NotFound
    record_remediation_error(error_type: :not_accessible)
    raise RepoNotAccessible
  end

  def necessary?
    return false if existing_account&.active? && existing_repo.present?

    true
  end

  private

  def find_or_create_account
    return existing_account if existing_account.present? && existing_account.active?

    # In Proxima, right now there is no way to determine the accounts'
    # `tenant_id` and `tenant_slug` at this point, so we need to bail out.
    return if Dependabot.proxima?

    if GitHubHelpers.onboard_account_with_global_app?(github_id: github_account_id)
      return SetupAccountWithGlobalApp.new(
        github_id: github_account_id,
        tenant_id: nil,
        tenant_slug: nil,
        event_source: event_source
      ).run
    end

    installation = repo_installation
    account = FindOrCreateAccount.new(github_account: installation[:account]).run
    account = ActivateAccount.new(account: account, installation_id: installation[:id],
                                  sender: installation[:account]).run

    record_remediation_success(remediation_type: :account)

    account
  end

  def existing_account
    return @existing_account if defined?(@existing_account)

    @existing_account ||= Account.find_by(github_id: github_account_id)
  end

  def find_or_create_repo(account)
    return existing_repo if existing_repo.present?

    repo_details = fetch_repo_details(account: account, github_id: github_repo_id)
    return unless repo_details

    repo = FindOrCreateRepo.new(github_repo: repo_details).run
    repo_settings = Dependabot::Application.dependabot_repository_settings_client.get_repository_settings(repo)
    repo.update!(
      security_updates_enabled: repo_settings.automated_security_updates_enabled,
    )

    record_remediation_success(remediation_type: :repo)

    repo
  end

  def existing_repo
    return @existing_repo if defined?(@existing_repo)

    @existing_repo ||= Repo.find_by(github_id: github_repo_id)
  end

  def fetch_repo_details(account:, github_id:)
    client = GitHubHelpers::ClientWithRetries.new(account: account)
    client.repo(github_id)
  rescue Octokit::UnavailableForLegalReasons
    nil
  end

  def repo_installation
    @repo_installation ||= app_github_client.find_repository_installation(github_repo_id)
  end

  def app_github_client
    GitHubHelpers::ClientWithRetries.new(
      bearer_token: GitHubHelpers.integration_token,
      etag_caching: true,
    )
  end

  def record_remediation_success(remediation_type:)
    Dependabot::Logger.info(
      "gh.dependabot_api.event.source": event_source,
      remediation_type: remediation_type,
      msg: "Successful remediation",
      "code.namespace": self.class.name.to_s,
      "gh.repo.id": github_repo_id,
      "gh.owner.id": github_account_id,
    )
    MetricsClient.increment("repo_activation_remediation.success",
                            tags: {
                              event_source: event_source,
                              remediation_type: remediation_type,
                            })
  end

  def record_remediation_error(error_type:)
    Dependabot::Logger.error(
      "gh.dependabot_api.event.source": event_source,
      error_type: error_type,
      msg: "Failed remediation",
      "code.namespace": self.class.name.to_s,
      "gh.repo.id": github_repo_id,
      "gh.owner.id": github_account_id,
    )
    MetricsClient.increment("repo_activation_remediation.error",
                            tags: {
                              event_source: event_source,
                              error_type: error_type,
                            })
  end
end
