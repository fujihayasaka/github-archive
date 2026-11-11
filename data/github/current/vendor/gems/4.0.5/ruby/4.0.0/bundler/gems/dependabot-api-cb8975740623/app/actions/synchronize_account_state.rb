# frozen_string_literal: true

require "github_helpers"

class SynchronizeAccountState
  def initialize(account:, event_source: "unknown")
    @account = account
    @event_source = event_source
  end

  def run
    if account.using_global_app?
      log_account_state("using-global-app")
      return
    end

    installation = fetch_installation_for_account

    app_github_client.installation(installation.id)

    if account.current_installation_id.to_i != installation.id.to_i
      activate_account(installation.id.to_i)
      log_account_state("account updated", new_installation_id: installation.id.to_i)
    else
      log_account_state("up-to-date")
    end
  rescue Octokit::NotFound
    deactivate_account
  end

  private

  attr_reader :account, :event_source

  def fetch_installation_for_account
    if account.user?
      app_github_client.find_user_installation(account.github_id)
    else
      app_github_client.find_organization_installation(account.github_id)
    end
  end

  def activate_account(installation_id)
    ActivateAccount.new(
      account: account,
      installation_id: installation_id,
      sender: { "login" => "unknown", "id" => 0 },
    ).run
  end

  def deactivate_account
    return log_account_state("already inactive") if account.in_state?(:inactive)

    log_account_state("deactivation pending")
    DeactivateAccount.new(
      account: account,
      installation_id: account.current_installation_id,
      sender: { "login" => "unknown", "id" => 0 },
      event_source: event_source,
    ).run
  end

  def app_github_client
    GitHubHelpers::ClientWithRetries.new(
      bearer_token: GitHubHelpers.integration_token,
      etag_caching: true,
    )
  end

  def log_account_state(state, **extra_context)
    Dependabot::Logger.info(
      "gh.dependabot_api.account.state": state,
      "code.namespace": "SynchronizeAccountState",
      "gh.owner.id": account.github_id,
      **extra_context
    )

    MetricsClient.increment("action.synchronize_account_state")
  end
end
