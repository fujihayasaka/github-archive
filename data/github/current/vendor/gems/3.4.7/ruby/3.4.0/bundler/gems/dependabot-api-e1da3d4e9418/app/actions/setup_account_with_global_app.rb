# frozen_string_literal: true

require "github_helpers"

# Onboards or reactivates an Account using our Global App capability
class SetupAccountWithGlobalApp
  attr_reader :github_id, :event_source, :tenant_id, :tenant_slug

  class AccountNotAccessible < StandardError; end
  class AccountNotFound < StandardError; end

  def initialize(github_id:, event_source:, tenant_id: nil, tenant_slug: nil)
    @github_id = github_id
    @event_source = event_source
    @tenant_id = tenant_id
    @tenant_slug = tenant_slug
  end

  def run
    find_or_create_account
  end

  private

  def find_or_create_account
    return existing_account if existing_account.present? && existing_account.active?

    account_details = fetch_account_details
    github_account = {
      id: account_details.id,
      type: account_details.type,
      login: account_details.login,
      tenant_id: tenant_id,
      tenant_slug: tenant_slug,
    }.with_indifferent_access
    account = FindOrCreateAccount.new(github_account: github_account).run
    ActivateAccount.new(account: account, installation_id: Account::GLOBAL_APP_INSTALLATION_ID,
                        sender: github_account).run
  end

  def existing_account
    return @existing_account if defined?(@existing_account)

    @existing_account ||= Account.find_by(github_id: github_id)
  end

  def fetch_account_details
    app_github_client.user(github_id)
  rescue Octokit::UnprocessableEntity
    raise AccountNotAccessible
  rescue Octokit::NotFound
    raise AccountNotFound
  end

  def app_github_client
    access_token = GitHubHelpers.global_access_token_for(github_id)
    GitHubHelpers::ClientWithRetries.new(
      access_token: access_token,
      bearer_token: GitHubHelpers.integration_token,
      etag_caching: true,
    )
  end
end
