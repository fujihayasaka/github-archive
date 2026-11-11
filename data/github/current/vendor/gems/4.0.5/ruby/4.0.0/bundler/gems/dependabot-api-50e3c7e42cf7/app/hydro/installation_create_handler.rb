# frozen_string_literal: true

class InstallationCreateHandler
  class InstallationNotFound < StandardError; end

  attr_reader :installation, :integration, :repositories, :sender

  def self.run(message)
    integration = message.value.fetch(:integration)
    repositories = message.value.fetch(:repositories, [])
    sender = message.value.fetch(:sender)

    installation = message.value.fetch(:installation)
    installation_with_tenant = installation.merge(
      tenant_id: message.headers.fetch("X-GitHub-Tenant-ID") { raise if Dependabot.proxima? },
      tenant_slug: message.headers.fetch("X-GitHub-Tenant") { raise if Dependabot.proxima? }
    )

    new(installation_with_tenant, integration, repositories, sender).run
  end

  def self.dead_letter_errors
    { InstallationCreateHandler::InstallationNotFound => false }
  end

  def initialize(installation, integration, repositories, sender)
    @installation = installation
    @integration = integration
    @repositories = repositories
    @sender = sender
  end

  def run
    return unless dependabot_installation?
    return unless valid_install_target?
    return if target_uses_global_app? # installation tracking isn't needed when using global apps

    account = create_install(
      installation: installation_params,
      github_account: github_account_params,
      sender: sender_params
    )

    repositories.each do |repo_params|
      SetupRepoJob.perform_later(account: account, github_id: repo_params[:id])
    end
  end

  private

  def create_install(installation:, github_account:, sender:)
    # Add the github user to the Failbot context
    Dependabot::Exceptions.push(
      "gh.owner.id": github_account[:id],
    )

    account = FindOrCreateAccount.new(
      github_account: github_account,
      repo_selection: installation[:repository_selection],
      event_source: "hydro",
    ).run
    ActivateAccount.new(
      account: account,
      installation_id: installation[:id],
      sender: sender,
    ).run

    log_installation_created(account, installation)
    account
  rescue ActivateAccount::InstallationNotFound
    # Re-raise class-specific error for clearer consumer dead-letter tracing
    raise InstallationNotFound
  end

  def log_installation_created(account, installation)
    Dependabot::Logger.info(
      msg: "Installation created",
      "code.namespace": "InstallationCreateHandler",
      "gh.owner.id": account.github_id,
      repository_selection: installation[:repository_selection],
    )
  end

  def dependabot_installation?
    integration[:id] == Prius.get(:github_integration_id)
  end

  def valid_install_target?
    installation[:target_type] != :BUSINESS
  end

  def target_uses_global_app?
    GitHubHelpers.onboard_account_with_global_app?(github_id: installation[:target_id])
  end

  def installation_params
    {
      id: installation[:id],
      repository_selection: installation[:repository_selection],
    }.with_indifferent_access
  end

  def github_account_params
    {
      id: installation[:target_id],
      type: installation[:target_type].to_s.capitalize,
      login: installation[:target_name],
      tenant_id: installation[:tenant_id],
      tenant_slug: installation[:tenant_slug],
    }.with_indifferent_access
  end

  def sender_params
    {
      id: sender[:id],
      login: sender[:login],
    }.with_indifferent_access
  end
end
