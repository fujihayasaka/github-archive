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

  # This endpoint deals with dismissing, reopening, or updating assignees for an alert
  # via RepositoryVulnerabilityAlert#dismiss, #reopen, or #update_assignees.
  # Neither dismiss nor reopen can be performed on a fixed alert.
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

    if data.has_key?("assignees")
      assignee_logins = data["assignees"].compact_blank.map(&:downcase).uniq
      if assignee_logins.any?
        valid_assignees = User.with_logins(assignee_logins).to_a
        if valid_assignees.size != assignee_logins.size
          missing = assignee_logins - valid_assignees.map { |u| u.display_login.downcase }
          deliver_error!(422, message: "#{missing.join(", ")} could not be found")
        end
      else
        valid_assignees = []
      end
    end

    if data.has_key?("state")
      if alert.state == "fixed"
        deliver_error!(409, message: "Fixed alerts cannot be dismissed or reopened")
      end

      if data["state"] == "dismissed"
        dismiss_alert(alert, data)
      else
        reopen_alert(alert, data)
      end
    end

    # Truthy when valid_assignees is an empty array (clear) or has items; nil when assignees key is absent.
    if valid_assignees
      begin
        alert.update_assignees(valid_assignees, current_user)
      rescue ActiveRecord::RecordInvalid => e
        deliver_error!(422, message: e.record.errors.full_messages.join(", "))
      end
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

    alerts = alerts_for_repository(repository: repo)

    deliver(:dependabot_alerts_hash, { alerts: alerts }, last_modified: calc_last_modified(alerts))

  rescue Platform::Errors::Cursor,
    Search::Queries::CursorPagination::ParameterError,
    Platform::Errors::DuplicateFirstLastPaginationBoundaries,
    Platform::Errors::ExcessivePagination,
    Platform::Errors::InvalidPagination => e

    deliver_error!(400, message: e.message)
  end
end
