# frozen_string_literal: true

class InstallationRepositoriesAddedHandler
  class MismatchedAccountError < StandardError; end

  attr_reader :installation, :repositories_added, :sender

  def self.run(message)
    installation = message.value.fetch(:installation)
    repositories_added = message.value.fetch(:repositories_added)
    sender = message.value.fetch(:sender)

    new(installation, repositories_added, sender).run
  end

  def self.dead_letter_errors
    { InstallationRepositoriesAddedHandler::MismatchedAccountError => false }
  end

  def initialize(installation, repositories_added, sender)
    @installation = installation
    @repositories_added = repositories_added
    @sender = sender
  end

  def run
    Dependabot::Exceptions.push(
      "gh.installation.id": @installation[:id],
      # Should be Account#github_id
      "gh.owner.id": @installation[:target_id],
    )

    return unless active_installation_exists?

    add_repositories(
      github_account: github_account_params,
      repositories_added: added_repository_params,
    )
  end

  private

  def add_repositories(github_account:, repositories_added:)
    # Add the github user to the Failbot context
    Dependabot::Exceptions.push(
      "gh.owner.id": github_account[:id],
    )

    account = lookup_account(github_account)
    return if account.using_global_app? # installation tracking isn't needed when using global apps

    repositories_added.map do |repo_details|
      # Delay repository setup by a second to compensate for replication lag
      # across dotcom.
      SetupRepoJob.set(wait: 1.second).perform_later(
        account: account,
        github_id: repo_details[:id],
      )
      log_repository_added(account, repo_details)
    end

    MetricsClient.increment("account.repositories_added",
                            tags: { event_source: :hydro })
  end

  def log_repository_added(account, repo_details)
    Dependabot::Logger.info(
      msg: "repository added",
      "code.namespace": "InstallationRepositoriesAddedHandler",
      "gh.owner.id": account.github_id,
      "gh.repo.id": repo_details[:id],
    )
  end

  def lookup_account(github_account)
    account_type = Account.map_account_type(github_account[:type])
    github_id = github_account[:id]
    FindOrUpdateAccount.new(github_id: github_id, type: account_type).run
  rescue ActiveRecord::RecordNotFound
    Dependabot::Logger.info(
      msg: "login not found",
      "code.namespace": "InstallationRepositoriesAddedHandler",
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

  def added_repository_params
    repositories_added.map do |repository|
      {
        id: repository[:id],
        name: repository[:name],
      }.with_indifferent_access
    end
  end
end
