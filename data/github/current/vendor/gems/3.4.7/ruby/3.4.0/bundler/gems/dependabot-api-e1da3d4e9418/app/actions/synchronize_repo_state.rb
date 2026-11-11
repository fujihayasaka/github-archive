# frozen_string_literal: true

require "github_helpers"

class SynchronizeRepoState # rubocop:disable Metrics/ClassLength
  class RepoTransferredError < StandardError; end

  class RepoArchivedError < StandardError; end

  HANDLED_ERRORS = [
    Dependabot::SyncError,
    GitHubHelpers::InvalidInstallationId,
    Octokit::BillingIssue,
    Octokit::NotFound,
    Octokit::RepositoryUnavailable,
    Octokit::UnavailableForLegalReasons,
    GitHub::Twirp::DependabotPullRequests::RepoStateServiceError,
  ].freeze

  TRADE_CONTROL_REPO_ERROR_PATTERN = /Please contact .+ to resolve the issue./
  TRADE_CONTROL_OWNER_ERROR_PATTERN = /Due to U.S. trade controls law restrictions/
  REPO_INSTALLATION_MISSING_PATTERN = /There is at least one repository that does not exist/
  REPO_MISSING_PATTERN = /No repositories were provided/
  BILLING_ISSUE_PATTERN = /billing issue/

  ACCOUNT_OUT_OF_SYNC = "account_out_of_sync"
  UNAVAILABLE_FOR_LEGAL_REASONS = "unavailable_for_legal_reasons"
  BILLING_ISSUE = "billing_issue"
  SPAMMY_ACCOUNT = "spammy_account"
  TRADE_CONTROL = "trade_control"
  MISSING_INSTALLATION = "missing_installation"
  INSTALLATION_LACKS_WRITE_ACCESS = "installation_lacks_write_access"
  REPO_DELETED = "repo_deleted"
  REPO_PRESENT = "repo_present"
  REPO_TEMPORARILY_UNAVAILABLE = "repo_temporarily_unavailable"
  DEPENDABOT_NOT_INSTALLED = "dependabot_not_installed"

  INTERMITTENT_SYNC_FAILURES = [
    INSTALLATION_LACKS_WRITE_ACCESS,
    MISSING_INSTALLATION,
    REPO_TEMPORARILY_UNAVAILABLE,
  ].freeze
  class SynchronizeRepoStateResult
    VALID_OUTCOMES = %i(success error).freeze

    attr_reader :reason, :repo_settings

    def self.success(repo_settings: nil)
      new(outcome: :success, repo_settings: repo_settings)
    end

    def self.error(reason:)
      new(outcome: :error, reason: reason)
    end

    def initialize(outcome:, reason: nil, repo_settings: nil)
      raise ArgumentError unless VALID_OUTCOMES.include? outcome

      @outcome = outcome

      raise ArgumentError if @outcome == :error && !reason

      @reason = reason
      @repo_settings = repo_settings
    end

    def success?
      @outcome == :success
    end

    def intermittent_failure?
      INTERMITTENT_SYNC_FAILURES.include? reason
    end

    def error?
      @outcome == :error
    end
  end

  def initialize(repo:, event_source: "syncronize_repo_state")
    @repo = repo
    @event_source = event_source
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def run
    return unless repo.account.active?

    instrument_synchronize_repo_state
    # Update any details we're storing on our side from GitHub.
    update_repo_and_account_details
    SynchronizeRepoStateResult.success(repo_settings: repository_settings)
  rescue Octokit::NotFound, Octokit::RepositoryUnavailable => e
    if account_spammy?
      deactivate_spammy_account

      log_account_out_of_sync(reason_for_resync: e)
      SynchronizeRepoStateResult.error(reason: SPAMMY_ACCOUNT)
    else
      SynchronizeAccountState.new(account: repo.account, event_source: event_source).run

      log_account_out_of_sync(reason_for_resync: e)
      if repo_actually_present?
        SynchronizeRepoStateResult.error(reason: REPO_TEMPORARILY_UNAVAILABLE)
      else
        SynchronizeRepoStateResult.error(reason: ACCOUNT_OUT_OF_SYNC)
      end
    end
  rescue RepoTransferredError, RepoArchivedError, GitHubHelpers::InvalidInstallationId => e
    if [RepoArchivedError, GitHubHelpers::InvalidInstallationId].include?(e.class)
      deactivate_repo(reason: ACCOUNT_OUT_OF_SYNC, error_message: e.message)
    end

    log_account_out_of_sync(reason_for_resync: e)
    SynchronizeRepoStateResult.error(reason: ACCOUNT_OUT_OF_SYNC)
  rescue Octokit::UnavailableForLegalReasons => e
    # In the event the Repository has been subject to a take-down it will not be
    # available via the API to sync account state, so we disable the update
    # config.
    deactivate_repo(reason: UNAVAILABLE_FOR_LEGAL_REASONS, error_message: e.message)
    SynchronizeRepoStateResult.error(reason: UNAVAILABLE_FOR_LEGAL_REASONS)
  rescue Dependabot::ResourceUnavailableToInstallation => e
    handle_resource_unavailable_to_installation(e)
  rescue Octokit::Forbidden => e
    handle_forbidden_error(e)
  rescue Octokit::UnprocessableEntity => e
    handle_unprocessable_error(e)
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  private

  attr_reader :repo, :event_source

  # rubocop:disable Metrics/AbcSize
  def update_repo_and_account_details
    github_repo_details = installation_github_client.repo(repo.github_id)

    unless repo.account.github_id == github_repo_details.owner.id
      new_account = find_github_user_account(github_repo_details.owner)
      TransferRepoAccountJob.perform_later(repo: repo, new_account: new_account)
      raise RepoTransferredError
    end

    raise RepoArchivedError if github_repo_details.archived

    repo_settings = repository_settings
    repo.update!(
      name: github_repo_details.name,
      default_branch: github_repo_details.default_branch,
      private: github_repo_details.private,
      primary_language: github_repo_details.language&.downcase,
      security_updates_enabled: repo_settings.automated_security_updates_enabled,
    )

    repo.account.update!(github_login: github_repo_details.owner.login)
  end
  # rubocop:enable Metrics/AbcSize

  def find_github_user_account(github_user)
    account_type =
      case github_user.type
      when "User" then "user"
      when "Organization" then "org"
      end
    Account.find_by(github_id: github_user.id, account_type: account_type)
  end

  def deactivate_repo(reason:, error_message: nil)
    Dependabot::Logger.info(
      msg: "deactivate repo",
      "code.namespace": "SynchronizeRepoState",
      reason: reason,
      "exception.message": error_message,
      "gh.repo.id": repo.github_id,
    )
    DeactivateRepo.new(repo_github_id: repo.github_id).run
  end

  def account_spammy?
    repo_presence_twirp_response == SPAMMY_ACCOUNT
  end

  def repo_actually_present?
    repo_presence_twirp_response == REPO_PRESENT
  end

  def deactivate_spammy_account
    Dependabot::Logger.info(
      msg: "deactivate spammy account",
      "code.namespace": "SynchronizeRepoState",
      "gh.owner.id": repo.account.github_id,
      "gh.repo.id": repo.github_id,
    )

    DeactivateAccount.new(
      account: repo.account,
      installation_id: repo.account.current_installation_id,
      sender: { "login" => "unknown", "id" => 0 },
      event_source: event_source,
    ).run
  end

  def handle_forbidden_error(error)
    if error.message.match?(BILLING_ISSUE_PATTERN)
      # If this repo has been disabled for billing reasons we quietly return and
      # don't disable the update config (since in future the repo may be
      # re-enabled).
      SynchronizeRepoStateResult.error(reason: BILLING_ISSUE)
    elsif blocked_by_trade_control?(error.message)
      # If this repo is unavailable due to a trade control restriction, it will
      # not be available via the API to sync account state, so we disable the
      # update config.
      deactivate_repo(reason: TRADE_CONTROL, error_message: error.message)
      SynchronizeRepoStateResult.error(reason: TRADE_CONTROL)
    else
      raise error
    end
  end

  def handle_unprocessable_error(error)
    # Use Twirp to check if the repo exists because it side-steps the token intermittent failures.
    result = deactivate_deleted_and_uninstalled_repos
    return result if result

    raise error unless outdated_installation?(error.message)

    # Dependabot isn't installed on the repository, this may be an intermittant state
    # See: https://github.com/github/dependabot-updates/issues/1137
    SynchronizeRepoStateResult.error(reason: MISSING_INSTALLATION)
  end

  def deactivate_deleted_and_uninstalled_repos
    response = repository_settings
    if response.dependabot_installed == false && repo.fork?
      deactivate_repo(reason: DEPENDABOT_NOT_INSTALLED)
      SynchronizeRepoStateResult.error(reason: DEPENDABOT_NOT_INSTALLED)
    end
  rescue GitHub::Twirp::DependabotRepositorySettings::NotFound => e
    deactivate_repo(reason: REPO_DELETED, error_message: e.message)
    SynchronizeRepoStateResult.error(reason: REPO_DELETED)
  end

  def outdated_installation?(message)
    message.match?(REPO_INSTALLATION_MISSING_PATTERN) ||
      message.match?(REPO_MISSING_PATTERN)
  end

  def blocked_by_trade_control?(message)
    message.match?(TRADE_CONTROL_REPO_ERROR_PATTERN) ||
      message.match?(TRADE_CONTROL_OWNER_ERROR_PATTERN)
  end

  def instrument_synchronize_repo_state
    Dependabot::Exceptions.push("gh.dependabot_api.event.source": event_source, "gh.repo.id": repo.github_id)
    Dependabot::Logger.info(
      msg: "run synchronize repo state",
      "code.namespace": "SynchronizeRepoState",
      "gh.dependabot_api.event.source": event_source,
      "gh.repo.id": repo.github_id,
    )
    MetricsClient.increment("action.synchronize_repo_state",
                            tags: { event_source: event_source })
  end

  def log_account_out_of_sync(reason_for_resync:)
    Dependabot::Logger.info(
      msg: "Account out of sync",
      "code.namespace": "SynchronizeRepoState",
      "gh.dependabot_api.event.source": event_source,
      "gh.repo.id": repo.github_id,
      twirp_presence_check: repo_presence_twirp_response,
      reason_for_resync: "#{reason_for_resync.class.name} - #{reason_for_resync.message}",
    )
    MetricsClient.increment("action.synchronize_repo_state.account_out_of_sync",
                            tags: { event_source: event_source })
  end

  def handle_resource_unavailable_to_installation(error)
    Dependabot::Logger.info(
      msg: "Resource unavailable to installation",
      "code.namespace": "SynchronizeRepoState",
      "exception.message": error.message,
      "gh.dependabot_api.event.source": event_source,
      "gh.repo.id": repo.github_id,
    )

    result = deactivate_deleted_and_uninstalled_repos
    return result if result

    SynchronizeRepoStateResult.error(reason: INSTALLATION_LACKS_WRITE_ACCESS)
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.new(
        account: repo.account,
        repo_ids: [repo.github_id],
        permissions: { contents: "read", metadata: "read" },
      )
  end

  def repo_presence_twirp_response
    @repo_presence_twirp_response ||= begin
      return REPO_PRESENT if repository_settings.present?
    rescue GitHub::Twirp::DependabotRepositorySettings::NotFound => e
      return SPAMMY_ACCOUNT if e.message.include?("is spammy")

      "repo not found"
    end
  end

  def repository_settings
    @repository_settings ||= Dependabot::Application.dependabot_repository_settings_client.get_repository_settings(repo)
  end
end
