# typed: true
# frozen_string_literal: true

class Api::EnterpriseDependabotAlerts < Api::Enterprise::App
  include Api::App::DependabotAlertsHelpers

  get "/enterprises/:enterprise_id/dependabot/alerts", operation_id: "dependabot/list-alerts-for-enterprise" do
    business = find_enterprise!

    #https://thehub.github.com/epd/engineering/products-and-services/public-apis/graphql/security/authorizing-objects/#github-app-access
    control_access :list_enterprise_dependabot_alerts,
      resource: business,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    ensure_non_conflicting_cursor_params!

    alerts = alerts_for_enterprise(business: business)

    deliver :dependabot_alerts_hash, { alerts: alerts }, include_repository: true, last_modified: calc_last_modified(alerts)
  rescue Platform::Errors::Cursor,
    Search::Queries::CursorPagination::ParameterError,
    Platform::Errors::DuplicateFirstLastPaginationBoundaries,
    Platform::Errors::ExcessivePagination,
    Platform::Errors::InvalidPagination => e

    deliver_error!(400, message: e.message)
  end
end
