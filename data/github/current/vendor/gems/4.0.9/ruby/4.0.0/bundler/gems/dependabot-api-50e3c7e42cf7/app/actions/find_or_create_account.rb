# frozen_string_literal: true

class FindOrCreateAccount
  attr_reader :github_account, :repo_selection, :event_source

  def initialize(github_account:,
                 repo_selection: "selected",
                 event_source: :unknown)
    @github_account = github_account
    @repo_selection = repo_selection
    # TODO: Remove `accounts.event_source` column (ETA: 2019-08-31)
    @event_source   = event_source
    # Event source tracks how many accounts we create via webhooks vs hydro.
    # This column/logic can be removed once we have completed this issue:
    # https://github.com/github/dependabot-api/issues/599
  end

  def run # rubocop:disable Metrics/MethodLength
    account_type = Account.map_account_type(github_account["type"])
    account = ActiveRecord::Base.connected_to(role: :reading) do
      Account.find_or_initialize_by(
        github_id: github_account["id"],
        account_type: account_type,
      )
    end

    set_account_defaults(account) unless account.persisted?
    tenant = find_or_create_tenant
    account.update!(
      github_login: github_account["login"],
      tenant: tenant,
    )

    account
  rescue ActiveRecord::RecordNotUnique
    # In the event of a race condition beating us we should be able to find the account at this point,
    ActiveRecord::Base.connected_to(role: :reading) do
      Account.find_by!(
        github_id: github_account["id"],
        account_type: account_type
      )
    end
  end

  private

  def find_or_create_tenant
    return nil unless Dependabot.proxima?

    Tenant.find_or_initialize_by(github_id: github_account["tenant_id"]).tap do |tenant|
      tenant.slug = github_account["tenant_slug"]
      tenant.shortcode = shortcode_from_login(github_account["login"])
      tenant.save! if tenant.changed?
    end
  end

  # rubocop:disable Naming/AccessorMethodName
  def set_account_defaults(account)
    account.assign_attributes(
      create_merge_commits: true,
      merge_on_approval: false,
      initial_update_runs_pr_limit:
        Account::DEFAULT_INITIAL_UPDATE_RUNS_PR_LIMIT,
      unlimited_private_repos_override: false,
      allow_automerging: false,
      event_source: event_source,
    )
  end
  # rubocop:enable Naming/AccessorMethodName

  def shortcode_from_login(login)
    return nil unless Dependabot.proxima?

    _username, shortcode = login.split("_")
    shortcode
  end
end
