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

  def run
    account_type = Account.map_account_type(github_account["type"])
    account = Account.find_or_initialize_by(
      github_id: github_account["id"],
      account_type: account_type,
    )
    set_account_defaults(account) unless account.persisted?

    tenant = Tenant.find_or_initialize_by(github_id: github_account["tenant_id"]) if Dependabot.proxima?
    tenant&.update!(slug: github_account["tenant_slug"], shortcode: shortcode_from_login(github_account["login"]))

    account.update!(
      github_login: github_account["login"],
      tenant: tenant,
    )
    account
  rescue ActiveRecord::RecordNotUnique
    # In the event of a race condition beating us we
    # should be able to find the account at this point,
    # if not we should raise
    Account.find_by!(
      github_id: github_account["id"],
      account_type: account_type
    )
  end

  private

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
