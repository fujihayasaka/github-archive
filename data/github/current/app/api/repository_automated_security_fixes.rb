# typed: true
# frozen_string_literal: true

class Api::RepositoryAutomatedSecurityFixes < Api::App
  include ReceiveSchemaWithOpenApi

  # check the status of the vulnerability alerts
  get "/repositories/:repository_id/automated-security-fixes", operation_id: "repos/check-automated-security-fixes" do
    deliver_error!(404) unless GitHub.dependabot_enabled?
    @accepted_scopes = %(repo)

    repo = find_repo!

    control_access(:read_automated_security_fixes,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    hash = {
      enabled: repo.vulnerability_updates_enabled?,
      paused: repo.dependabot_updates_paused?
    }
    deliver(:raw, hash)
  end

  # enable automated security fixes for a repo
  put "/repositories/:repository_id/automated-security-fixes", operation_id: "repos/enable-automated-security-fixes" do
    @accepted_scopes = %(repo)
    deliver_error! 404 unless GitHub.dependabot_enabled?

    repo = find_repo!

    control_access(:admin_automated_security_fixes,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    ensure_vulnerability_alerts_enabled(repo: repo)

    receive_with_schema("repository-automated-security-fixes-setting", "enable")

    _, error = repo.enable_vulnerability_updates(actor: current_user)

    if repo.vulnerability_updates_enabled?
      deliver_empty(status: 204)
    else
      deliver_error!(422, message: SecurityProduct::VulnerabilityUpdates.error_to_message(error))
    end
  end

  # disable automated security fixes for a repo
  delete "/repositories/:repository_id/automated-security-fixes", operation_id: "repos/disable-automated-security-fixes" do
    @accepted_scopes = %(repo)
    deliver_error! 404 unless GitHub.dependabot_enabled?

    repo = find_repo!

    control_access(:admin_automated_security_fixes,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    ensure_vulnerability_alerts_enabled(repo: repo)

    receive_with_schema("repository-automated-security-fixes-setting", "disable")

    _, error = repo.disable_vulnerability_updates(actor: current_user)

    if repo.vulnerability_updates_enabled?
      deliver_error!(422, message: SecurityProduct::VulnerabilityUpdates.error_to_message(error))
    else
      deliver_empty(status: 204)
    end
  end

  private

  def ensure_vulnerability_alerts_enabled(repo:)
    unless repo.vulnerability_alerts_enabled?
      deliver_error!(422, message: "Vulnerability alerts must be enabled to configure automated security fixes.")
    end
  end
end
