# frozen_string_literal: true

class InstallationDeleteHandler
  class MissingAccountError < StandardError; end

  attr_reader :installation, :integration, :sender

  def self.run(message)
    integration = message.value.fetch(:integration)
    sender = message.value.fetch(:sender)

    installation = message.value.fetch(:installation)
    installation_with_tenant = installation.merge(
      tenant_id: message.headers.fetch("X-GitHub-Tenant-ID") { raise if Dependabot.proxima? }
    )

    new(installation_with_tenant, integration, sender).run
  end

  def self.dead_letter_errors
    { InstallationDeleteHandler::MissingAccountError => false }
  end

  def initialize(installation, integration, sender)
    @installation = installation
    @integration = integration
    @sender = sender
  end

  def run
    return unless dependabot_installation?
    return unless valid_install_target?

    remove_install(
      installation: installation_params,
      github_account: github_account_params,
      sender: sender_params
    )
  end

  private

  def remove_install(installation:, github_account:, sender:)
    # Add the github user to the Failbot context
    Dependabot::Exceptions.push(
      "gh.owner.id": github_account[:id],
      "gh.installation.id": installation[:id],
    )

    account = account_for(github_account)
    return if account.using_global_app? # installation tracking isn't needed when using global apps

    # Distributed systems sometimes have lag in message buses.  Don't attempt to deactivate an account
    # if it's already been activated with another installation.
    return if account.in_state?(:active) && account.current_installation_id != installation[:id]

    DeactivateAccount.new(
      account: account,
      installation_id: installation[:id],
      sender: sender,
      event_source: "webhook.installation_deleted"
    ).run
  end

  def account_for(github_account)
    account_type =
      case github_account[:type]
      when "User" then "user"
      when "Organization" then "org"
      end

    Account.find_by!(
      github_id: github_account[:id],
      account_type: account_type,
    )
  rescue ActiveRecord::RecordNotFound
    raise MissingAccountError, "account never created"
  end

  def dependabot_installation?
    integration[:id] == Prius.get(:github_integration_id)
  end

  def valid_install_target?
    installation[:target_type] != :BUSINESS
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
    }.with_indifferent_access
  end

  def sender_params
    return {} unless sender

    {
      id: sender[:id],
      login: sender[:login],
    }.with_indifferent_access
  end
end
