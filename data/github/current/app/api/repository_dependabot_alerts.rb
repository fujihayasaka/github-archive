# typed: true
# frozen_string_literal: true

class Api::RepositoryDependabotAlerts < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::DependabotAlertsHelpers

  FORBIDDEN_MESSAGE = "You are not authorized to perform this operation."

  # Get a specific Dependabot alert by number
  get "/repositories/:repository_id/dependabot/alerts/:alert_number", operation_id: "dependabot/get-alert" do
    repo = find_repo!
    ensure_repo_access_and_dependabot_alerts_enabled!(repo)

    control_access :read_vulnerability_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    alert = find_alert!(repo)

    deliver(:dependabot_alert_hash, alert, last_modified: calc_last_modified_for_object(alert))
  end

  # This endpoint deals with with dismissing or reopening an alert via RepositoryVulnerabilityAlert#dismiss or #reopen.
  # Neither of these operations can be performed on a fixed alert.
  patch "/repositories/:repository_id/dependabot/alerts/:alert_number", operation_id: "dependabot/update-alert" do
    repo = find_repo!
    ensure_repo_access_and_dependabot_alerts_enabled!(repo)

    control_access :write_vulnerability_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    alert = find_alert!(repo)
    data = receive_with_openapi

    if alert.state == "fixed"
      deliver_error!(409, message: "Fixed alerts cannot be dismissed or reopened")
    end

    if data["state"] == "dismissed"
      dismiss_alert(alert, data)
    else
      reopen_alert(alert, data)
    end

    deliver(:dependabot_alert_hash, alert)
  end

  get "/repositories/:repository_id/dependabot/alerts", operation_id: "dependabot/list-alerts-for-repo" do
    repo = find_repo!
    ensure_repo_access_and_dependabot_alerts_enabled!(repo)

    control_access :read_vulnerability_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    ensure_non_conflicting_cursor_params!

    alerts = alerts_for_repository(repository: repo, cursor_pagination: using_cursor_based_pagination?)

    deliver(:dependabot_alerts_hash, { alerts: alerts }, last_modified: calc_last_modified(alerts))

  rescue Platform::Errors::Cursor,
    Platform::Errors::DuplicateFirstLastPaginationBoundaries,
    Platform::Errors::ExcessivePagination,
    Platform::Errors::InvalidPagination => e

    deliver_error!(400, message: e.message)
  end
end
