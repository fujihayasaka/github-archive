# typed: true
# frozen_string_literal: true

class Api::OrganizationDependabotAlerts < Api::App
  include Api::App::DependabotAlertsHelpers

  # List Dependabot alerts for an organization
  get "/organizations/:organization_id/dependabot/alerts", operation_id: "dependabot/list-alerts-for-org" do
    org = find_org!

    control_access :list_org_dependabot_alerts,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_non_conflicting_cursor_params!

    alerts = alerts_for_organization(organization: org)

    deliver :dependabot_alerts_hash, { alerts: alerts }, include_repository: true, last_modified: calc_last_modified(alerts)
  rescue Platform::Errors::Cursor,
    Search::Queries::CursorPagination::ParameterError,
    Platform::Errors::DuplicateFirstLastPaginationBoundaries,
    Platform::Errors::ExcessivePagination,
    Platform::Errors::InvalidPagination => e

    deliver_error!(400, message: e.message)
  end
end
