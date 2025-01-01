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

    fgp = :view_dependabot_alerts
    authorized_org_ids = T.must(
      ::SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
        actor: current_user,
        business:,
        actions: fgp,
        cap_filter:,
      ).authorized_orgs_by_action[fgp]
    ).map(&:id)

    ensure_non_conflicting_cursor_params!

    alerts = alerts_for_enterprise(business: business, organization_ids: authorized_org_ids, cursor_pagination: using_cursor_based_pagination?)

    deliver :dependabot_alerts_hash, { alerts: alerts }, include_repository: true, last_modified: calc_last_modified(alerts)
  rescue Platform::Errors::Cursor,
    Platform::Errors::DuplicateFirstLastPaginationBoundaries,
    Platform::Errors::ExcessivePagination,
    Platform::Errors::InvalidPagination => e

    deliver_error!(400, message: e.message)
  end
end
