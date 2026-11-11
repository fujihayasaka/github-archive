# frozen_string_literal: true

class InstallationRepositoriesRemovedHandler
  class MismatchedAccountError < StandardError; end

  attr_reader :installation, :repositories_removed, :sender

  def self.run(message)
    installation = message.value.fetch(:installation)
    repositories_removed = message.value.fetch(:repositories_removed)
    sender = message.value.fetch(:sender)

    new(installation, repositories_removed, sender).run
  end

  def self.dead_letter_errors
    { InstallationRepositoriesRemovedHandler::MismatchedAccountError => false }
  end

  def initialize(installation, repositories_removed, sender)
    @installation = installation
    @repositories_removed = repositories_removed
    @sender = sender
  end

  def run
    return unless active_installation_exists?

    remove_repositories(
      github_account: github_account_params,
      sender: sender_params
    )
  end

  private

  # rubocop:disable Metrics/MethodLength
  def remove_repositories(github_account:, sender:)
    if repositories_removed.length > 1
      Dependabot::Logger.info(
        msg: "removal of more than 1 repository",
        "code.namespace": "InstallationRepositoriesRemovedHandler",
        "gh.owner.id": github_account[:id],
      )
    end

    # Add the github user to the Failbot context
    Dependabot::Exceptions.push(
      "gh.owner.id": github_account[:id],
    )

    MetricsClient.increment("account.repositories_removed",
                            tags: { event_source: :hydro })

    account = lookup_account(github_account)

    # We can only update the installed repository list if the account
    # is currently active and can call back to dotcom.
    return unless account.active?

    return if account.using_global_app? # installation tracking isn't needed when using global apps

    repositories_removed.each do |repo_details|
      DeactivateRepoJob.perform_later(
        repo_github_id: repo_details[:id],
        user: sender,
      )
    end
  rescue Octokit::NotFound
    # If we can't find the account anymore, it has been deleted and we will
    # have received an installation delete message, so do nothing.
  end
  # rubocop:enable Metrics/MethodLength

  def lookup_account(github_account)
    account_type = Account.map_account_type(github_account[:type])
    github_id = github_account[:id]
    FindOrUpdateAccount.new(github_id: github_id, type: account_type).run
  rescue ActiveRecord::RecordNotFound
    Dependabot::Logger.info(
      msg: "login not found",
      "code.namespace": "InstallationRepositoriesRemovedHandler",
      "gh.owner.id": github_account[:id],
    )
    raise MismatchedAccountError, "login not found"
  end

  def active_installation_exists?
    AccountTransition.exists?(most_recent: true,
                              to_state: :active,
                              installation_id: installation[:id])
  end

  def github_account_params
    {
      id: installation[:target_id],
      type: installation[:target_type],
      login: installation[:target_name],
    }.with_indifferent_access
  end

  def sender_params
    return DeactivateRepo::UNKNOWN_USER unless sender

    {
      id: sender[:id],
      login: sender[:login],
    }.with_indifferent_access
  end
end
